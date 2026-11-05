"""Build real ELF modules to check the port's mixed C++ runtime isolation."""

import ctypes
import os
from pathlib import Path
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
add_library(ggml-base STATIC base.cpp)
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


@unittest.skipUnless(CXX and CC and shutil.which("cmake"), "Clang and CMake required")
class RuntimeIsolation(unittest.TestCase):
    def run_command(self, args, success=True):
        result = subprocess.run(args, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def check_modules(self, files, xdna=False, success=True):
        return self.run_command([
            "cmake", "-DQVAC_CHECK_FILES=" + ";".join(map(str, files)),
            "-DQVAC_CHECK_XDNA=" + ("ON" if xdna else "OFF"),
            "-P", str(PORT / "qvac-check-cxx-runtime.cmake"),
        ], success=success)

    def build_modules(self, cuda, xdna):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "CMakeLists.txt").write_text(FIXTURE)
            (root / "base.cpp").write_text(
                '#include <string>\nextern "C" int ggml_probe(int n) { '
                "return std::string(n, 'x').size(); }\n")
            (root / "cpu.cpp").write_text(
                '#include <string>\nextern "C" int ggml_probe(int);\n'
                'extern "C" int cpu_probe(int n) { '
                "return ggml_probe(n) + std::string(n, 'y').size(); }\n")
            (root / "cuda.cpp").write_text(
                'extern "C" int ggml_probe(int);\n'
                'extern "C" int ggml_backend_init(int n) { return ggml_probe(n); }\n')
            (root / "xdna.cpp").write_text(
                'extern "C" int cpu_probe(int);\nextern "C" int xrt_probe(void);\n'
                'extern "C" int ggml_backend_init(int n) { '
                'return cpu_probe(n) + xrt_probe(); }\n')
            (root / "xrt.c").write_text("int xrt_probe(void) { return 1; }\n")
            build = root / "build"
            self.run_command([
                "cmake", "-S", str(root), "-B", str(build),
                "-DCMAKE_C_COMPILER=" + CC, "-DCMAKE_CXX_COMPILER=" + CXX,
                "-DRUNTIME_HOOK=" + str(PORT / "linux-cxx-runtime.cmake"),
                "-DWITH_CUDA=" + ("ON" if cuda else "OFF"),
                "-DWITH_XDNA=" + ("ON" if xdna else "OFF"),
            ])
            self.run_command(["cmake", "--build", str(build), "-j", "2"])
            self.assertEqual(len(list(build.rglob("libggml-base-libstdcxx.a"))), 1)
            modules = []
            if cuda:
                module = build / "libqvac-ggml-cuda.so"
                self.check_modules([module])
                self.assertEqual(ctypes.CDLL(str(module)).ggml_backend_init(128), 128)
                exports = self.run_command(["nm", "-D", "--defined-only", str(module)]).stdout
                self.assertNotIn("ggml_probe", exports)
                modules.append(module)
            if xdna:
                module = build / "libqvac-ggml-xdna.so"
                self.check_modules([module], success=False)
                self.check_modules([module], xdna=True)
                self.assertEqual(ctypes.CDLL(str(module)).ggml_backend_init(128), 257)
                exports = self.run_command(["nm", "-D", "--defined-only", str(module)]).stdout
                self.assertNotIn("ggml_probe", exports)
                modules.append(module)
                # The XDNA opt-in must not exempt another backend's runtime.
                bad = build / "libqvac-ggml-other.so"
                shutil.copy2(module, bad)
                self.check_modules([module, bad], xdna=True, success=False)
            self.check_modules(modules, xdna=xdna)

    def test_cuda_only(self):
        self.build_modules(cuda=True, xdna=False)

    def test_xdna_only(self):
        self.build_modules(cuda=False, xdna=True)

    def test_cuda_and_xdna_share_one_archive(self):
        self.build_modules(cuda=True, xdna=True)


if __name__ == "__main__":
    unittest.main()
