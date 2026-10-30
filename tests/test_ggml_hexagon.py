from pathlib import Path
import os
import subprocess
import tempfile
import unittest

PORT = Path(__file__).resolve().parents[1] / "ports" / "ggml-speech"


def run_port(hexagon, with_skeletons):
    with tempfile.TemporaryDirectory(prefix="ggml-hexagon-") as temporary:
        root = Path(temporary)
        skeletons = "\n".join(
            f'file(WRITE "${{CURRENT_PACKAGES_DIR}}/lib/libggml-htp-v{version}.so" "DSP{version}")'
            for version in (73, 75, 79, 81)
        ) if with_skeletons else ""
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
set(FEATURES "{'hexagon' if hexagon else ''}")
function(vcpkg_from_github)
  set(SOURCE_PATH "{root.as_posix()}/source" PARENT_SCOPE)
endfunction()
function(vcpkg_cmake_configure)
  cmake_parse_arguments(PARSE_ARGV 0 captured "" "" "OPTIONS")
  file(WRITE "{root.as_posix()}/options.txt" "${{captured_OPTIONS}}")
endfunction()
function(vcpkg_cmake_install)
  file(MAKE_DIRECTORY "${{CURRENT_PACKAGES_DIR}}/lib")
  {skeletons}
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
        result, options = run_port(False, False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(options["GGML_HEXAGON"], "OFF")

    def test_opt_in_build_forwards_sdk_paths_and_installs_skeletons(self):
        result, options = run_port(True, True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(options["GGML_HEXAGON"], "ON")
        self.assertTrue(options["HEXAGON_SDK_ROOT"].endswith("SDK path"))
        self.assertTrue(options["HEXAGON_TOOLS_ROOT"].endswith("Tools path"))
        self.assertEqual(options["PREBUILT_LIB_DIR"], "android_aarch64")

    def test_opt_in_build_rejects_missing_dsp_skeletons(self):
        result, _ = run_port(True, False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matching DSP skeletons were not installed", result.stderr)


if __name__ == "__main__":
    unittest.main()
