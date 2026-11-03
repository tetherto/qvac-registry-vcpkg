from pathlib import Path
import os
import subprocess
import tempfile
import unittest

PORT = Path(__file__).resolve().parents[1] / "ports" / "ggml-speech"


def run_port(hexagon):
    with tempfile.TemporaryDirectory(prefix="ggml-hexagon-") as temporary:
        root = Path(temporary)
        script = root / "test.cmake"
        script.write_text(f'''
cmake_minimum_required(VERSION 3.25)
set(CURRENT_PACKAGES_DIR "{root.as_posix()}/packages")
set(CURRENT_BUILDTREES_DIR "{root.as_posix()}/buildtrees")
set(CURRENT_INSTALLED_DIR "{root.as_posix()}/installed")
set(VCPKG_BUILD_TYPE release)
set(VCPKG_TARGET_IS_ANDROID ON)
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(TARGET_TRIPLET arm64-android)
set(PORT ggml-speech)
set(FEATURES "")
function(vcpkg_from_github)
  set(SOURCE_PATH "{root.as_posix()}/source" PARENT_SCOPE)
endfunction()
function(vcpkg_cmake_configure)
  cmake_parse_arguments(PARSE_ARGV 0 captured "" "" "OPTIONS")
  file(WRITE "{root.as_posix()}/options.txt" "${{captured_OPTIONS}}")
  file(MAKE_DIRECTORY "${{CURRENT_BUILDTREES_DIR}}/${{TARGET_TRIPLET}}-rel")
  file(WRITE "${{CURRENT_BUILDTREES_DIR}}/${{TARGET_TRIPLET}}-rel/CMakeCache.txt" "GGML_HEXAGON:BOOL={'ON' if hexagon else 'OFF'}\n")
endfunction()
function(vcpkg_cmake_install)
  file(MAKE_DIRECTORY "${{CURRENT_PACKAGES_DIR}}/lib")
endfunction()
function(vcpkg_cmake_config_fixup)
endfunction()
function(vcpkg_fixup_pkgconfig)
endfunction()
function(vcpkg_install_copyright)
endfunction()
include("{(PORT / 'portfile.cmake').as_posix()}")
''')
        result = subprocess.run(["cmake", "-P", str(script)], capture_output=True, text=True,
                                env={**os.environ, "HEXAGON_SDK_ROOT": str(root / "SDK path"),
                                     "HEXAGON_TOOLS_ROOT": str(root / "Tools path")})
        options = (root / "options.txt").read_text().split(";")
        return result, dict(option[2:].split("=", 1) for option in options if option.startswith("-D"))


class HexagonPort(unittest.TestCase):
    def test_default_build_has_no_dsp_requirement(self):
        result, options = run_port(False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(options["GGML_HEXAGON"], "OFF")

    def test_cached_hexagon_build_is_rejected(self):
        result, options = run_port(True)
        self.assertEqual(options["GGML_HEXAGON"], "OFF")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must not build or ship", result.stderr)



if __name__ == "__main__":
    unittest.main()
