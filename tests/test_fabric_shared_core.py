"""Exercise shared libc++ plus GNU backend linkage without GPU hardware/SDKs."""

from pathlib import Path
import ctypes
import shutil
import tempfile
import unittest

from test_fabric_libstdcxx_runtime import RuntimeIsolation, FIXTURE, PORT


class SharedCoreIsolation(RuntimeIsolation):
    # The legacy layout has its own tests in the imported module.
    test_cuda_only = None
    test_xdna_only = None
    test_cuda_and_xdna_share_one_archive = None

    def test_shared_core_and_gnu_backends(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = FIXTURE.replace(
                "add_library(ggml-base STATIC base.cpp)",
                "add_library(ggml-base SHARED base.cpp)\n"
                "set_target_properties(ggml-base PROPERTIES OUTPUT_NAME qvac-ggml-base-1)\n"
                "add_library(ggml SHARED registry.cpp)\n"
                "target_link_libraries(ggml PRIVATE ggml-base)\n"
                "set_target_properties(ggml PROPERTIES OUTPUT_NAME qvac-ggml-1)\n"
                'set(GGML_AVAILABLE_BACKENDS "ggml-cuda;ggml-xdna")')
            (root / "CMakeLists.txt").write_text(fixture)
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
            from test_fabric_libstdcxx_runtime import CC, CXX
            build = root / "build"
            self.run_command([
                "cmake", "-S", str(root), "-B", str(build),
                "-DCMAKE_C_COMPILER=" + CC, "-DCMAKE_CXX_COMPILER=" + CXX,
                "-DRUNTIME_HOOK=" + str(PORT / "linux-cxx-runtime.cmake"),
                "-DWITH_CUDA=ON", "-DWITH_XDNA=ON", "-DGGML_SHARED_CORE=ON",
            ])
            self.run_command(["cmake", "--build", str(build), "-j", "2"])
            self.assertEqual(list(build.rglob("libggml-base-libstdcxx.a")), [])
            modules = [build / ("libqvac-ggml-" + name + ".so") for name in ["cuda", "xdna"]]
            check = root / "check.cmake"
            check.write_text(
                'include("' + str(PORT / "qvac-check-cxx-runtime.cmake") + '")\n'
                'include("' + str(PORT / "qvac-check-shared-core.cmake") + '")\n'
                'file(GLOB modules "' + str(build) + '/libqvac-*.so")\n'
                'qvac_check_shared_core(WITH_XDNA ${modules})\n')
            self.run_command(["cmake", "-P", str(check)])
            for module, expected in zip(modules, [128, 129]):
                self.assertEqual(ctypes.CDLL(str(module)).ggml_backend_init(128), expected)
                imports = self.run_command(["nm", "-D", "--undefined-only", str(module)]).stdout
                self.assertIn("ggml_probe@QVAC_GGML_BASE_ABI_1", imports)
                self.assertNotRegex(imports, r"_Z[^\n]*@QVAC_GGML_BASE_ABI_1")
            # A copied module losing its required XDNA identity must fail closed.
            shutil.copy2(modules[1], build / "libqvac-ggml-other.so")
            self.run_command(["cmake", "-P", str(check)], success=False)


if __name__ == "__main__":
    unittest.main()
