"""Exercise the port check against real ELF modules, including #5461's failure."""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


CHECK = Path(__file__).resolve().parents[1] / "ports/ggml-speech/qvac-check-cxx-runtime.cmake"


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux ELF modules only")
class SpeechCxxRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for tool in ("cc", "c++", "cmake"):
            self.assertIsNotNone(shutil.which(tool), f"required test tool: {tool}")

    def build(self, source, *, cxx=False):
        src = self.root / ("fixture.cpp" if cxx else "fixture.c")
        module = self.root / "fixture.so"
        src.write_text(source)
        subprocess.run(
            ["c++" if cxx else "cc", "-shared", "-fPIC", str(src), "-o", str(module)],
            check=True, capture_output=True, text=True,
        )
        return module

    def check_module(self, module):
        return subprocess.run(
            ["cmake", f"-DQVAC_CHECK_FILES={module}", "-P", str(CHECK)],
            capture_output=True, text=True,
        )

    def test_module_without_shared_cxx_runtime_passes(self):
        module = self.build("int ggml_backend_init(void) { return 1; }\n")
        result = self.check_module(module)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_undefined_std_symbol_without_needed_runtime_fails(self):
        # A C link reproduces nvcc host code's missing runtime reference
        # without adding the libstdc++ DT_NEEDED that would normally supply it.
        module = self.build(
            'extern void missing(void) __asm__("_ZNSt18condition_variable10notify_allEv");\n'
            "void ggml_backend_init(void) { missing(); }\n"
        )
        result = self.check_module(module)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("_ZNSt18condition_variable10notify_allEv", result.stderr)
        self.assertIn("1 undefined C++ runtime symbols", result.stderr)

    def test_shared_cxx_runtime_dependency_fails(self):
        module = self.build(
            '#include <string>\nextern "C" unsigned ggml_backend_init(const char *s) '
            "{ return std::string(s).size(); }\n",
            cxx=True,
        )
        result = self.check_module(module)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NEEDED:", result.stderr)


if __name__ == "__main__":
    unittest.main()
