# whisper-cpp: pinned at tetherto/qvac-ext-lib-whisper.cpp@master HEAD
# a34cb6da. The only whisper-root change since the previous pin (738d2e9e,
# the v1.8.5 sync, PR #33) is PR #34's KV-cache CPU-buffer fallback: when a
# single K/V tensor exceeds the backend's max single-tensor size, the cache
# is allocated from the CPU buffer-type so the K/V ops run on CPU while the
# rest of the model stays on GPU (Adreno-740 whisper-cli fix). All other
# master commits since that pin touch the parakeet-cpp/, tts-cpp/, or
# vendored ggml/ trees, which this port does not build
# (WHISPER_USE_SYSTEM_GGML=ON links the ggml-speech-installed ggml instead).
#
vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-lib-whisper.cpp
  REF a34cb6da6d4b7c1d7a81d8543b29b818422b6a52
  SHA512 b0e80b06b4460267d39f7daddd9e6a25b9981fb8cd31504f85dc3d6c04871c2eff4cc86972120f0d3a280bef0bacd806da7b5e16f0e409e7ef88a6294fd99937
  HEAD_REF master
  PATCHES
    patches/0001-move-gnuinstalldirs-before-add-subdirectory-src.patch
)

# whisper-cpp consumes the system-installed ggml provided by the `ggml-speech`
# port (same shape as the `parakeet-cpp` and `tts-cpp` ports). Backend
# selection, Android dynamic-backend packaging, Vulkan-Headers download,
# spirv-headers include shim, per-arch CPU variants and the
# libqvac-speech-ggml-* filename prefix are all owned by `ggml-speech`; this
# port only carries whisper-specific build options and links against the
# installed ggml via `find_package(ggml)` (gated by WHISPER_USE_SYSTEM_GGML).
#
# Per-feature wiring lives in vcpkg.json:
#   whisper-cpp[metal]  -> ggml-speech[metal]   (osx | ios)
#   whisper-cpp[vulkan] -> ggml-speech[vulkan]  (linux | windows | android)
#   whisper-cpp[opencl] -> ggml-speech[opencl]  (android)
# so consumers express the full GPU matrix declaratively.

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
  OPTIONS
    -DWHISPER_USE_SYSTEM_GGML=ON
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_BUILD_EXAMPLES=OFF
    -DWHISPER_BUILD_SERVER=OFF
    -DBUILD_SHARED_LIBS=OFF
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(
  PACKAGE_NAME whisper
  CONFIG_PATH share/whisper
)

vcpkg_fixup_pkgconfig()

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

# whisper-cpp itself produces no shared libraries when BUILD_SHARED_LIBS=OFF.
# The ggml backend .so files (Android dynamic-backend mode) are installed by
# the ggml-speech port into ${VCPKG_INSTALLED_DIR}/<triplet>/lib/, not by us.
if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
