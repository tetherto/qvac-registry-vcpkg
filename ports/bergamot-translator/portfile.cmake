vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-bergamot-translator
  # 277df45 = merge of qvac-ext-bergamot-translator#19 into temp-vcpkg.
  # That is 99ef81e (the 1.0.1 pin: port-enabled lineage plus the stderr
  # print removal) plus dropping CMAKE_STATIC_LINKER_FLAGS
  # /LTCG:incremental, which llvm-lib rejects.
  REF 277df45
  SHA512 6d8098c951a671477247b2bcb50f94f7120eea3a91359954e9e9c4fe2f21f91654dbcb539cdbb720c6b1f665f08471ca21e14e0baaa795d18500633be33831a2
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
