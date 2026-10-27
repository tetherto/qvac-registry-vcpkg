import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REGISTRY = Path(__file__).resolve().parents[1]
PORT = REGISTRY / "ports" / "speech-cpp"
MOCKED_COMMANDS = (
    "vcpkg_cmake_install",
    "vcpkg_cmake_config_fixup",
    "vcpkg_fixup_pkgconfig",
    "vcpkg_install_copyright",
)


def mock_commands():
    return "\n".join(f"function({name})\nendfunction()" for name in MOCKED_COMMANDS)


def harness(vcpkg):
    return f'''
cmake_minimum_required(VERSION 3.24)
include("{vcpkg.as_posix()}/scripts/cmake/vcpkg_check_features.cmake")
file(MAKE_DIRECTORY "${{TEST_ROOT}}/source" "${{CURRENT_INSTALLED_DIR}}/share/ggml")
file(WRITE "${{TEST_ROOT}}/source/CMakeLists.txt" "")
file(WRITE "${{CURRENT_INSTALLED_DIR}}/share/ggml/ggml-config.cmake" "set(GGML_HEXAGON OFF)\n")
file(MAKE_DIRECTORY "${{CURRENT_PACKAGES_DIR}}/share/tts-cpp")
file(WRITE "${{CURRENT_PACKAGES_DIR}}/share/tts-cpp/tts-cppConfig.cmake" "find_dependency(ggml CONFIG)\n")
function(vcpkg_from_github)
    set(SOURCE_PATH "${{TEST_ROOT}}/source" PARENT_SCOPE)
endfunction()
function(vcpkg_cmake_configure)
    cmake_parse_arguments(PARSE_ARGV 0 captured "" "" "OPTIONS;MAYBE_UNUSED_VARIABLES")
    file(WRITE "${{TEST_ROOT}}/options.txt" "${{captured_OPTIONS}}")
endfunction()
{mock_commands()}
include("{(PORT / 'portfile.cmake').as_posix()}")
'''


def platform_options(platform):
    targets = ("osx", "ios", "linux", "windows", "android")
    return [f"-DVCPKG_TARGET_IS_{target.upper()}={'ON' if target == platform else 'OFF'}" for target in targets]


def feature_options(features, platform):
    vcpkg = Path(os.environ["VCPKG_ROOT"]).resolve()
    with tempfile.TemporaryDirectory(prefix="speech-cpp-features-") as temporary:
        root = Path(temporary)
        script = root / "test.cmake"
        script.write_text(harness(vcpkg))
        command = [
            "cmake",
            f"-DTEST_ROOT={root}",
            f"-DCURRENT_INSTALLED_DIR={root / 'installed'}",
            f"-DCURRENT_PACKAGES_DIR={root / 'packages'}",
            f"-DCURRENT_BUILDTREES_DIR={root / 'buildtrees'}",
            "-DPORT=speech-cpp",
            "-DVCPKG_LIBRARY_LINKAGE=static",
            *platform_options(platform),
            f"-DFEATURES={';'.join(features)}",
            "-P",
            str(script),
        ]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        options = (root / "options.txt").read_text().split(";")
        return dict(option[2:].split("=", 1) for option in options if option.startswith("-D"))


class SpeechCppFeatures(unittest.TestCase):
    def test_audiogen_enables_full_minimax_coreml_on_macos(self):
        options = feature_options(["audiogen"], "osx")
        self.assertEqual(options.get("AUDIOGEN_MINIMAX_COREML", "OFF"), "ON")
        self.assertEqual(options["SPEECH_BUILD_AUDIOGEN"], "ON")
        self.assertEqual(options["AUDIOGEN_COREML"], "OFF")
        self.assertEqual(options["TTS_CPP_COREML"], "OFF")
        self.assertEqual(options["PARAKEET_COREML"], "OFF")

    def test_non_macos_audiogen_keeps_full_minimax_coreml_disabled(self):
        for platform in ("linux", "windows", "android", "ios"):
            with self.subTest(platform=platform):
                options = feature_options(["audiogen"], platform)
                self.assertEqual(options.get("AUDIOGEN_MINIMAX_COREML", "OFF"), "OFF")
                self.assertEqual(options["SPEECH_BUILD_AUDIOGEN"], "ON")

    def test_other_engines_keep_full_minimax_coreml_disabled(self):
        options = feature_options(["tts"], "osx")
        self.assertEqual(options.get("AUDIOGEN_MINIMAX_COREML", "OFF"), "OFF")
        self.assertEqual(options["SPEECH_BUILD_AUDIOGEN"], "OFF")

    def test_existing_coreml_feature_stays_independent(self):
        options = feature_options(["tts", "coreml"], "osx")
        self.assertEqual(options.get("AUDIOGEN_MINIMAX_COREML", "OFF"), "OFF")
        self.assertEqual(options["TTS_CPP_COREML"], "ON")
        self.assertEqual(options["PARAKEET_COREML"], "ON")
        self.assertEqual(options["AUDIOGEN_COREML"], "ON")

    def test_audiogen_combines_with_existing_coreml_feature(self):
        options = feature_options(["audiogen", "coreml"], "osx")
        self.assertEqual(options.get("AUDIOGEN_MINIMAX_COREML", "OFF"), "ON")
        self.assertEqual(options["AUDIOGEN_COREML"], "ON")

    def test_minimax_does_not_require_a_separate_feature(self):
        manifest = json.loads((PORT / "vcpkg.json").read_text())
        self.assertIn("audiogen", manifest["features"])
        self.assertNotIn("minimax-coreml", manifest["features"])


if __name__ == "__main__":
    unittest.main()
