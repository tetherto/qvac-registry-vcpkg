vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-bergamot-translator
  REF b6788a8
  SHA512 21c65ae927c2d2ddb85914d66bcceb6e54dd62b3c25118ef69fb3d66e51d4bc24ea52a4f05ff4b68d01c634bb4b1c42af537ba1d50e56c4b07535845dd293995
  PATCHES
    remove_build_type_flag.patch
)

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
)

vcpkg_cmake_build()
vcpkg_cmake_install()

vcpkg_cmake_config_fixup(
  PACKAGE_NAME bergamot-translator
  CONFIG_PATH share/bergamot-translator
)

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
