vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO browsermt/simd_utils
  REF d0793d86aea9036a5bc77b9ca7791dff024168ca
  SHA512 d0baa7aa40840a552c12375815084c7e3995727341ef3def12611b4c7007abbff33d5dd5046d3d3a921e86a7e27a7d2f8d3c210a3418c29a6944c5402fd44c4b
  HEAD_REF master
  PATCHES
    0001-Add-necessary-cmake-install-files.patch
)

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
)

vcpkg_cmake_install()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
