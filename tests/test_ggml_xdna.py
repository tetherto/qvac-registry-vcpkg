from pathlib import Path
import subprocess
import tempfile
import unittest


PORT = Path(__file__).resolve().parents[1] / "ports" / "ggml-speech"


def run_port(features, install_kernel):
    with tempfile.TemporaryDirectory(prefix="ggml-xdna-") as temporary:
        root = Path(temporary)
        script = root / "test.cmake"
        script.write_text(f'''
cmake_minimum_required(VERSION 3.25)
set(CURRENT_PACKAGES_DIR "{root}/packages")
set(CURRENT_BUILDTREES_DIR "{root}/buildtrees")
set(CURRENT_INSTALLED_DIR "{root}/installed")
set(VCPKG_BUILD_TYPE release)
set(VCPKG_TARGET_IS_LINUX ON)
set(VCPKG_TARGET_ARCHITECTURE x64)
set(TARGET_TRIPLET x64-linux)
set(PORT ggml-speech)
set(FEATURES "{';'.join(features)}")
set(QVAC_NM /usr/bin/true)
set(QVAC_READELF /usr/bin/true)
function(vcpkg_from_github)
  set(SOURCE_PATH "{root}/source" PARENT_SCOPE)
endfunction()
function(vcpkg_cmake_configure)
  cmake_parse_arguments(PARSE_ARGV 0 captured "" "" "OPTIONS")
  file(WRITE "{root}/options.txt" "${{captured_OPTIONS}}")
  file(MAKE_DIRECTORY "${{CURRENT_BUILDTREES_DIR}}/${{TARGET_TRIPLET}}-rel")
  file(WRITE "${{CURRENT_BUILDTREES_DIR}}/${{TARGET_TRIPLET}}-rel/CMakeCache.txt" "GGML_HEXAGON:BOOL=OFF\n")
endfunction()
function(vcpkg_cmake_install)
  file(MAKE_DIRECTORY "${{CURRENT_PACKAGES_DIR}}/lib")
  file(WRITE "${{CURRENT_PACKAGES_DIR}}/lib/libqvac-speech-ggml-cpu.so" "module")
  if({str(install_kernel).upper()})
    foreach(stem IN ITEMS gemm_bf16_f32_M32_K1024_N2048_c8 gemm_bf16_f32_M256_K1024_N2048_c8)
      file(WRITE "${{CURRENT_PACKAGES_DIR}}/lib/${{stem}}.xclbin" "kernel")
      file(WRITE "${{CURRENT_PACKAGES_DIR}}/lib/${{stem}}.insts.bin" "instructions")
    endforeach()
  endif()
endfunction()
function(vcpkg_cmake_config_fixup)
endfunction()
function(vcpkg_fixup_pkgconfig)
endfunction()
function(vcpkg_install_copyright)
endfunction()
include("{PORT / 'portfile.cmake'}")
''')
        result = subprocess.run(["cmake", "-P", str(script)], capture_output=True, text=True)
        options = (root / "options.txt").read_text().split(";")
        return result, dict(option[2:].split("=", 1) for option in options if option.startswith("-D"))


class XdnaPort(unittest.TestCase):
    def test_default_build_does_not_enable_xdna(self):
        result, options = run_port([], False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(options["GGML_XDNA"], "OFF")

    def test_xdna_requires_packaged_kernels(self):
        result, options = run_port(["xdna"], False)
        self.assertEqual(options["GGML_XDNA"], "ON")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing gemm_bf16_f32_M32_K1024_N2048_c8.xclbin", result.stderr)

    def test_xdna_package_with_kernels(self):
        result, options = run_port(["xdna"], True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(options["GGML_XDNA"], "ON")


if __name__ == "__main__":
    unittest.main()
