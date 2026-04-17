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
# Pinned to the 2026-03-01 branch of the downstream fork (master-514-5792c66
# plus the squashed qvac-registry-vcpkg port patches).
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tetherto/qvac-ext-stable-diffusion.cpp
    REF b474457d6cd58499d4d7ec9ad17825eba11791de
    SHA512 628629b4bb76660f35b46bdc8941f108b6c5e932d53c739d660c217d2d9dc0293791b7c9d8176b15377d7a8cef52cec9c5533131cab69a0c59cf2da894b2c905
    HEAD_REF 2026-03-01
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
