vcpkg_from_git(
  OUT_SOURCE_PATH SOURCE_PATH
  URL git@github.com:tetherto/qvac.git
  REF 7c82411df507cf23d71d6edabccaadadb6323349
)

vcpkg_check_features(
  OUT_FEATURE_OPTIONS FEATURE_OPTIONS
  FEATURES
    tests BUILD_TESTING
)

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}/packages/qvac-lib-inference-addon-cpp/"
  DISABLE_PARALLEL_CONFIGURE
  OPTIONS
    ${FEATURE_OPTIONS}
)

vcpkg_cmake_install()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug")

file(
  INSTALL "${SOURCE_PATH}/packages/qvac-lib-inference-addon-cpp/LICENSE"
  DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}"
  RENAME copyright
)
