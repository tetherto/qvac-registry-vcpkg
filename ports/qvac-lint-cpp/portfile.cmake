set(QVAC_REPO "https://github.com/tetherto/qvac.git")
set(QVAC_REF "3f56abff423e21fc5ac79627cc43e1161bb7caaf")
set(QVAC_LINT_CPP_SUBDIR "packages/qvac-lint-cpp")

vcpkg_from_git(
  OUT_SOURCE_PATH SOURCE_PATH
  URL "${QVAC_REPO}"
  REF "${QVAC_REF}")

set(LINT_CPP_SOURCE_PATH "${SOURCE_PATH}/${QVAC_LINT_CPP_SUBDIR}")
vcpkg_cmake_configure(SOURCE_PATH "${LINT_CPP_SOURCE_PATH}")

vcpkg_cmake_install()

set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug")

set(LINT_CPP_LICENSE "${LINT_CPP_SOURCE_PATH}/LICENSE")
if(NOT EXISTS "${LINT_CPP_LICENSE}")
  set(LINT_CPP_LICENSE "${SOURCE_PATH}/LICENSE")
endif()
vcpkg_install_copyright(FILE_LIST "${LINT_CPP_LICENSE}")
