# stable-diffusion.cpp vcpkg overlay port
#
# Builds the stable-diffusion.cpp inference library and links against the
# system-installed ggml (provided by the separate ggml overlay port).
#
# Installed artefacts:
#   include/stable-diffusion.h   (main C API)
#   lib/libstable-diffusion.a    (static library)
#   share/stable-diffusion-cpp/  (CMake package config)
#
# GPU backend selection is handled at runtime via ggml's backend registry.
# The downstream fork replaces SD's backend-specific init with
# ggml_backend_init_by_type() which works with both statically linked and
# dynamically loaded backends.
#
# Pinned to 2aff3324 -- the tip of the 2026-06-04 branch, which rebases all
# qvac downstream patches (vcpkg port patches, ESRGAN upscaler device API,
# Wan 2.1 I2V VAE tiling fix, fused Flux RoPE) onto the upstream 2026-06-04
# base (zero Wan2.2 TI2V timesteps, chunk-K LoRA residency, img_uncond refactor).
# The ggml git submodule has been removed; ggml is provided entirely via
# SD_USE_SYSTEM_GGML from the vcpkg ggml port (tetherto/qvac-ext-ggml).
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tetherto/qvac-ext-stable-diffusion.cpp
    REF 1f267562f1a1bc1f82ed1a72fa7c39b6cba7f6dc
    SHA512 92dffd0189c3efd6e6b9a7a8d197fcfcd79d5a74f7d79efc42991d2273a646dc1586fdd1187c12a7b2e483597baa9b074ca97d0c83821715fb0bd2ddc2e4fd0c
    HEAD_REF 2026-06-04
)

set(SD_FLASH_ATTN OFF)

if("flash-attn" IN_LIST FEATURES)
    set(SD_FLASH_ATTN ON)
endif()

# Only build Release — debug builds are not needed for the prebuild and can
# fail with MSVC iterator-debug-level mismatches.
set(VCPKG_BUILD_TYPE release)

# --- Configure & build ---
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DSD_BUILD_EXAMPLES=OFF
        -DSD_BUILD_SHARED_LIBS=OFF
        -DSD_USE_SYSTEM_GGML=ON
        -DSD_FLASH_ATTN=${SD_FLASH_ATTN}
    MAYBE_UNUSED_VARIABLES
        SD_FLASH_ATTN
)

vcpkg_cmake_install()

# --- CMake package config ---
# Upstream does not export a CMake config, so we ship our own that defines
# stable-diffusion::stable-diffusion with ggml as a transitive dependency.
file(INSTALL
    "${CMAKE_CURRENT_LIST_DIR}/stable-diffusion-cppConfig.cmake"
    "${CMAKE_CURRENT_LIST_DIR}/stable-diffusion-cppConfigVersion.cmake"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/stable-diffusion-cpp"
)

# --- Cleanup ---
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
