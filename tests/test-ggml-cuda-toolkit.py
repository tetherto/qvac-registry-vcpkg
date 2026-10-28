"""Validate the server CUDA contract without installing CUDA or building ggml."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


PORT = Path(__file__).resolve().parents[1] / "ports/ggml"
ARCHS = "75-virtual;80-virtual;80-real;86-real;89-real;90-virtual;120a-real;121a-real"


class ToolkitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ggml-cuda-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ)
        for key in ("CUDACXX", "CUDA_PATH", "QVAC_CUDA_TOOLKIT"):
            self.env.pop(key, None)

    def compiler(self, name, version="V13.0.88", status=0):
        path = self.root / name / "bin/nvcc"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"#!/bin/sh\nprintf '%s\\n' '{version}'\nexit {status}\n")
        path.chmod(0o755)
        return path

    def run_cmake(self, source):
        script = self.root / "test.cmake"
        script.write_text("cmake_minimum_required(VERSION 3.25)\n" + source)
        result = subprocess.run(
            ["cmake", "-P", str(script)], env=self.env, text=True, capture_output=True
        )
        return result.returncode, result.stdout + result.stderr

    def run_helper(self):
        return self.run_cmake(
            f'include("{PORT.as_posix()}/cuda-toolkit.cmake")\n'
            'qvac_ggml_cuda_options(options)\n'
            'function(configure)\n'
            '  foreach(i RANGE 0 ${ARGC})\n'
            '    message(STATUS "ARG=${ARGV${i}}")\n'
            '  endforeach()\n'
            'endfunction()\n'
            'configure(${options})\n'
        )

    def test_explicit_compiler_and_root_win_with_one_architecture_argument(self):
        pinned = self.compiler("pinned toolkit")
        wrong = self.compiler("wrong", "V13.3.73")
        self.env.update(CUDACXX=str(pinned), CUDA_PATH=str(wrong.parent.parent),
                        QVAC_CUDA_TOOLKIT="13.0.3-server")
        code, output = self.run_helper()
        self.assertEqual(code, 0, output)
        self.assertIn("ARG=-DCMAKE_CUDA_COMPILER=" + str(pinned), output)
        self.assertIn("ARG=-DCUDAToolkit_ROOT=" + str(pinned.parent.parent), output)
        self.assertIn("ARG=-DCMAKE_CUDA_ARCHITECTURES=" + ARCHS + "\n", output)

    def test_cuda_path_wins_over_path(self):
        pinned = self.compiler("pinned")
        wrong = self.compiler("wrong", "V13.3.73")
        self.env.update(CUDA_PATH=str(pinned.parent.parent), QVAC_CUDA_TOOLKIT="13.0.3-server")
        self.env["PATH"] = str(wrong.parent) + os.pathsep + self.env["PATH"]
        code, output = self.run_helper()
        self.assertEqual(code, 0, output)
        self.assertIn("ARG=-DCMAKE_CUDA_COMPILER=" + str(pinned), output)

    def test_release_compiler_mismatch_is_fatal(self):
        self.env.update(CUDACXX=str(self.compiler("wrong", "V13.3.73")),
                        QVAC_CUDA_TOOLKIT="13.0.3-server")
        code, output = self.run_helper()
        self.assertNotEqual(code, 0)
        self.assertIn("expected 13.0.88", " ".join(output.split()))

    def test_wrong_toolkit_identity_is_fatal(self):
        self.env.update(CUDACXX=str(self.compiler("pinned")), QVAC_CUDA_TOOLKIT="wrong-toolkit")
        code, output = self.run_helper()
        self.assertNotEqual(code, 0)
        self.assertIn("does not match 13.0.3-server", " ".join(output.split()))

    def test_missing_explicit_compiler_does_not_fall_back(self):
        self.env.update(CUDACXX=str(self.root / "missing"),
                        CUDA_PATH=str(self.compiler("valid").parent.parent))
        code, output = self.run_helper()
        self.assertNotEqual(code, 0)
        self.assertIn("cannot query nvcc", output)

    def test_missing_explicit_toolkit_does_not_fall_back(self):
        self.env["CUDA_PATH"] = str(self.root / "missing")
        self.assertNotEqual(self.run_helper()[0], 0)

    def test_failed_version_query_is_fatal(self):
        self.env["CUDACXX"] = str(self.compiler("failed", status=2))
        self.assertNotEqual(self.run_helper()[0], 0)

    def test_unparseable_version_is_fatal(self):
        self.env["CUDACXX"] = str(self.compiler("invalid", "not a version"))
        code, output = self.run_helper()
        self.assertNotEqual(code, 0)
        self.assertIn("cannot parse nvcc version", output)

    def test_unpinned_developer_build_warns(self):
        self.env["CUDACXX"] = str(self.compiler("local", "V13.3.73"))
        code, output = self.run_helper()
        self.assertEqual(code, 0, output)
        self.assertIn("unpinned local CUDA", output)

    def test_toolkit_too_old_for_server_architectures_is_fatal(self):
        self.env["CUDACXX"] = str(self.compiler("old", "V12.8.93"))
        code, output = self.run_helper()
        self.assertNotEqual(code, 0)
        self.assertIn("require CUDA 12.9", output)

    def run_port(self, cuda=True, module=False):
        self.env["CUDACXX"] = str(self.compiler("pinned")) if cuda else str(self.root / "missing")
        packages = self.root / "packages"
        buildtrees = self.root / "buildtrees"
        packages.mkdir()
        if module:
            modules = buildtrees / "arm64-linux-rel/bin"
            modules.mkdir(parents=True)
            (modules / "libqvac-diffusion-ggml-cuda.so").write_bytes(b"fixture")
        return self.run_cmake(
            'set(VCPKG_TARGET_IS_LINUX TRUE)\n'
            'set(TARGET_TRIPLET arm64-linux)\n'
            f'set(FEATURES "{"cuda" if cuda else ""}")\n'
            f'set(CURRENT_PACKAGES_DIR "{packages.as_posix()}")\n'
            f'set(CURRENT_BUILDTREES_DIR "{buildtrees.as_posix()}")\n'
            'set(PORT ggml)\n'
            'foreach(command vcpkg_from_github vcpkg_cmake_install vcpkg_cmake_config_fixup '
            'vcpkg_fixup_pkgconfig vcpkg_install_copyright)\n'
            '  function(${command})\n  endfunction()\n'
            'endforeach()\n'
            'function(vcpkg_cmake_configure)\n'
            '  foreach(i RANGE 0 ${ARGC})\n'
            '    message(STATUS "ARG=${ARGV${i}}")\n'
            '  endforeach()\n'
            'endfunction()\n'
            f'include("{PORT.as_posix()}/portfile.cmake")\n'
        )

    def test_missing_cuda_module_fails_packaging(self):
        code, output = self.run_port()
        self.assertNotEqual(code, 0)
        self.assertIn("expected CUDA module was not installed", output)

    def test_port_forwards_architectures_and_installs_module(self):
        code, output = self.run_port(module=True)
        self.assertEqual(code, 0, output)
        self.assertIn("ARG=-DCMAKE_CUDA_ARCHITECTURES=" + ARCHS + "\n", output)
        self.assertTrue((self.root / "packages/lib/libqvac-diffusion-ggml-cuda.so").exists())

    def test_non_cuda_build_needs_no_toolkit_or_cuda_module(self):
        code, output = self.run_port(cuda=False)
        self.assertEqual(code, 0, output)
        self.assertNotIn("-DCMAKE_CUDA_ARCHITECTURES=", output)


if __name__ == "__main__":
    unittest.main()
