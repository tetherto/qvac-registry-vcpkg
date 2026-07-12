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
# Pulls from the tetherto/qvac-ext-stable-diffusion.cpp GitHub branch
# 2026-07-03 (REF pinned to the branch tip for reproducibility).
#
# f02a0b5 is the tip of 2026-07-03 after merging PR #19. It includes the
# 5832f9a size-reduction baseline plus Ideogram 4 support: Qwen3-VL
# conditioning, the Ideogram 4 runner, and
# sd_ctx_params_t::uncond_diffusion_model_path for loading the standalone
# unconditional CFG diffusion weights.
#
# fe394ca was the tip of 2026-07-03 — 2026-06-04-ltx (the merge of #13 into the
# 2026-06-04 base) plus one commit. The base carries the general qvac patches
# (vcpkg port patches, ESRGAN upscaler device API, Wan 2.1 I2V VAE tiling fix),
# while the merged -ltx delta adds fused Flux RoPE, the ggml public leaf-API
# migration, the CLI GPU-default tweak, the MSVC /bigobj fix for C1128, and
# exposes sd_ctx_params_t::backend for explicit backend pinning. The extra commit
# lets sd_resolve_backend_name() match a backend by its ggml registry name (e.g.
# "Vulkan0") in addition to device type.
#
# The vendored ggml submodule is kept on the -ltx branch for standalone
# (non-vcpkg) builds (SD_USE_SYSTEM_GGML defaults to OFF there), but this port
# builds with -DSD_USE_SYSTEM_GGML=ON so ggml is provided by the vcpkg ggml port
# (tetherto/qvac-ext-ggml@2026-07-03).
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tetherto/qvac-ext-stable-diffusion.cpp
    REF f02a0b5502e0e2e446549d2ceb837a9951b51883
    SHA512 da17ed79d069b3ed5cb921ba67f6ed7d3dd62104a574044449f3c3145cbc60259c52b4953115b5723e7737172edb70aebcc57c9f364625be95843a75344c026e
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
