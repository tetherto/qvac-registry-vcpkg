"""Exercise shared libc++ plus GNU backend linkage without GPU hardware/SDKs."""

from pathlib import Path
import ctypes
import os
import shutil
import subprocess
import tempfile
import unittest

PORT = Path(__file__).resolve().parents[1] / "ports" / "qvac-fabric"
CXX = os.environ.get("QVAC_TEST_CXX", shutil.which("clang++"))
CC = os.environ.get("QVAC_TEST_CC", shutil.which("clang"))

FIXTURE = r'''
cmake_minimum_required(VERSION 3.25)
project(runtime_fixture LANGUAGES C CXX)
set(CMAKE_CXX_FLAGS "-stdlib=libc++")
set(CMAKE_MODULE_LINKER_FLAGS "-stdlib=libc++ -static-libstdc++")
# CMake can add this implicitly after target libraries when CUDA is enabled.
set(CMAKE_CXX_STANDARD_LIBRARIES "-lstdc++")
include("${RUNTIME_HOOK}")
add_library(ggml-base SHARED base.cpp)
set_target_properties(ggml-base PROPERTIES OUTPUT_NAME qvac-ggml-base-1)
add_library(ggml SHARED registry.cpp)
target_link_libraries(ggml PRIVATE ggml-base)
set_target_properties(ggml PROPERTIES OUTPUT_NAME qvac-ggml-1)
set(GGML_AVAILABLE_BACKENDS ggml-cuda ggml-xdna)
set_target_properties(ggml-base PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(WITH_CUDA)
  # The hook checks the real CUDA compiler's directory property. The fixture
  # uses C++ sources to test final linkage without requiring a CUDA toolkit.
  set(CMAKE_CUDA_COMPILER_ID NVIDIA)
  add_library(ggml-cuda MODULE cuda.cpp)
  target_link_libraries(ggml-cuda PRIVATE ggml-base)
  set_target_properties(ggml-cuda PROPERTIES OUTPUT_NAME qvac-ggml-cuda)
endif()
if(WITH_XDNA)
  add_library(xrt SHARED xrt.c)
  set_target_properties(xrt PROPERTIES OUTPUT_NAME xrt_coreutil SOVERSION 2)
  add_library(ggml-cpu-xdna STATIC cpu.cpp)
  set_target_properties(ggml-cpu-xdna PROPERTIES POSITION_INDEPENDENT_CODE ON)
  target_link_libraries(ggml-cpu-xdna PRIVATE ggml-base)
  add_library(ggml-xdna MODULE xdna.cpp)
  target_link_libraries(ggml-xdna PRIVATE ggml-base ggml-cpu-xdna xrt)
  set_target_properties(ggml-xdna PROPERTIES OUTPUT_NAME qvac-ggml-xdna)
endif()
'''


@unittest.skipUnless(CXX and CC and shutil.which("cmake") and os.environ.get("QVAC_FABRIC_SOURCE"), "Set QVAC_FABRIC_SOURCE to the pinned fork checkout")
class SharedCoreIsolation(unittest.TestCase):
    def run_command(self, args, success=True):
        result = subprocess.run(args, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def build_modules(self, cuda, xdna):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = Path(os.environ["QVAC_FABRIC_SOURCE"]) / "ggml/src"
            hook = root / "runtime.cmake"
            hook.write_text(
                'include("' + str(source / "linux-cxx-runtime.cmake") + '")\n'
                'include("' + str(source / "shared-core-runtime.cmake") + '")\n'
                'cmake_language(DEFER CALL qvac_configure_cxx_runtimes)\n'
                'cmake_language(DEFER CALL qvac_configure_shared_core_runtime)\n')
            (root / "CMakeLists.txt").write_text(FIXTURE)
            (root / "base.cpp").write_text(
                '#include <string>\nextern "C" int ggml_probe(int n) { '
                "return std::string(n, 'x').size(); }\n")
            (root / "registry.cpp").write_text(
                'extern "C" int ggml_probe(int);\n'
                'extern "C" int ggml_backend_probe(int n) { return ggml_probe(n); }\n')
            (root / "cpu.cpp").write_text(
                'extern "C" int ggml_probe(int);\n'
                'extern "C" int cpu_probe(int n) { return ggml_probe(n); }\n')
            # Overlapping std::runtime_error symbols must resolve to GNU, even
            # though the core is on the link line and exports libc++ first.
            for name, body in [("cuda", "ggml_probe(n)"), ("xdna", "cpu_probe(n) + xrt_probe()")]:
                (root / (name + ".cpp")).write_text(
                    '#include <stdexcept>\n#include <cstring>\n'
                    'extern "C" int ggml_probe(int);\n'
                    'extern "C" int cpu_probe(int);\nextern "C" int xrt_probe();\n'
                    'extern "C" int ggml_backend_init(int n) { '
                    'std::runtime_error e("probe"); '
                    'if (std::strcmp(e.what(), "probe")) return -1; return ' + body + '; }\n')
            (root / "xrt.c").write_text("int xrt_probe(void) { return 1; }\n")
            build = root / "build"
            self.run_command([
                "cmake", "-S", str(root), "-B", str(build),
                "-DCMAKE_C_COMPILER=" + CC, "-DCMAKE_CXX_COMPILER=" + CXX,
                "-DRUNTIME_HOOK=" + str(hook),
                "-DWITH_CUDA=" + ("ON" if cuda else "OFF"),
                "-DWITH_XDNA=" + ("ON" if xdna else "OFF"),
            ])
            self.run_command(["cmake", "--build", str(build), "-j", "2"])
            self.assertEqual(list(build.rglob("libggml-base-libstdcxx.a")), [])
            names = (["cuda"] if cuda else []) + (["xdna"] if xdna else [])
            modules = [build / ("libqvac-ggml-" + name + ".so") for name in names]
            check = root / "check.cmake"
            check.write_text(
                'include("' + str(PORT / "qvac-check-cxx-runtime.cmake") + '")\n'
                'include("' + str(PORT / "qvac-check-shared-core.cmake") + '")\n'
                'file(GLOB modules "' + str(build) + '/libqvac-*.so")\n'
                'qvac_check_shared_core(' + ('WITH_XDNA ' if xdna else '') + '${modules})\n')
            self.run_command(["cmake", "-P", str(check)])
            for name, module in zip(names, modules):
                expected = 128 if name == "cuda" else 129
                self.assertEqual(ctypes.CDLL(str(module)).ggml_backend_init(128), expected)
                imports = self.run_command(["nm", "-D", "--undefined-only", str(module)]).stdout
                self.assertIn("ggml_probe@QVAC_GGML_BASE_ABI_1", imports)
                self.assertNotRegex(imports, r"_Z[^\n]*@QVAC_GGML_BASE_ABI_1")
            if xdna:
                # A copied module losing its required XDNA identity must fail closed.
                shutil.copy2(build / "libqvac-ggml-xdna.so", build / "libqvac-ggml-other.so")
                self.run_command(["cmake", "-P", str(check)], success=False)

    def test_cuda_only(self):
        self.build_modules(cuda=True, xdna=False)

    def test_xdna_only(self):
        self.build_modules(cuda=False, xdna=True)

    def test_cuda_and_xdna(self):
        self.build_modules(cuda=True, xdna=True)


if __name__ == "__main__":
    unittest.main()
