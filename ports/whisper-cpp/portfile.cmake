# whisper-cpp: pinned at tetherto/qvac-ext-lib-whisper.cpp@master HEAD
# 128dae42 (post-PR-#31 supertonic_optimizations merge). The whisper-root
# tree is unchanged since the previous pin (a34cb6da, PR #34 KV-cache
# CPU-buffer fallback); we move this port together with parakeet-cpp and
# tts-cpp so all three registry ports source the same master commit and
# the same archive SHA512. PR #31 only touches the tts-cpp/ tree (and the
# tts-cpp port re-bumps for it), which this port does not build
# (WHISPER_USE_SYSTEM_GGML=ON links the ggml-speech-installed ggml instead).
#
vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-lib-whisper.cpp
  REF 128dae4284fae3636ef5b6272ef123401d67eab7
  SHA512 195bfcfc74c36149fa5827f5c500c8144411b7a5709601f238773782bb5aa5c81599867f0c6f915f63e3b2c11557231d04bf2df208b5d3228e973af41e38df89
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
