from pathlib import Path
import subprocess
import tempfile
import unittest

PORT = Path(__file__).resolve().parents[1] / 'ports' / 'ggml'


def run_port(platform, ship_cpu=True):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        prefix, suffix = ('', '.dll') if platform == 'WINDOWS' else ('lib', '.so')
        module = f'{prefix}qvac-diffusion-ggml-cpu{suffix}'
        script = root / 'test.cmake'
        script.write_text(f'''
cmake_minimum_required(VERSION 3.25)
set(PORT ggml)
set(VCPKG_TARGET_IS_{platform} ON)
set(VCPKG_TARGET_SHARED_LIBRARY_PREFIX "{prefix}")
set(VCPKG_TARGET_SHARED_LIBRARY_SUFFIX "{suffix}")
set(TARGET_TRIPLET test-target)
set(CURRENT_PACKAGES_DIR "{root.as_posix()}/package")
set(CURRENT_BUILDTREES_DIR "{root.as_posix()}/build")
set(FEATURES "")
function(vcpkg_from_github)
  set(SOURCE_PATH "{root.as_posix()}/source" PARENT_SCOPE)
endfunction()
function(vcpkg_cmake_configure)
  cmake_parse_arguments(PARSE_ARGV 0 captured "" "" "OPTIONS")
  file(WRITE "{root.as_posix()}/options.txt" "${{captured_OPTIONS}}")
endfunction()
function(vcpkg_cmake_install)
  file(MAKE_DIRECTORY "${{CURRENT_PACKAGES_DIR}}/lib")
  if({str(ship_cpu).upper()})
    file(MAKE_DIRECTORY "${{CURRENT_BUILDTREES_DIR}}/${{TARGET_TRIPLET}}-rel/bin")
    file(WRITE "${{CURRENT_BUILDTREES_DIR}}/${{TARGET_TRIPLET}}-rel/bin/{module}" "module")
  endif()
endfunction()
function(vcpkg_cmake_config_fixup)
endfunction()
function(vcpkg_fixup_pkgconfig)
endfunction()
function(vcpkg_install_copyright)
endfunction()
include("{(PORT / 'portfile.cmake').as_posix()}")
''')
        result = subprocess.run(['cmake', '-P', str(script)], capture_output=True, text=True)
        options = (root / 'options.txt').read_text()
        installed = (root / 'package/lib' / module).exists()
        return result, options, installed


class DynamicCpuPort(unittest.TestCase):
    def test_cpu_module_is_configured_and_packaged(self):
        for platform in ('LINUX', 'ANDROID', 'WINDOWS'):
            with self.subTest(platform=platform):
                result, options, installed = run_port(platform)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('-DGGML_BACKEND_DL=ON', options)
                self.assertIn('-DGGML_CPU_STATIC=OFF', options)
                self.assertTrue(installed)

    def test_missing_cpu_module_fails_packaging(self):
        for platform in ('LINUX', 'ANDROID', 'WINDOWS'):
            with self.subTest(platform=platform):
                result, _, _ = run_port(platform, False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('required CPU module was not installed', result.stderr)


if __name__ == '__main__':
    unittest.main()
