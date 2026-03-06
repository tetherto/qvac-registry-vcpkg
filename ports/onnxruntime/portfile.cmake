message(STATUS ">>> Building custom onnxruntime port with platform-specific patches")

# Common patches
set(ONNXRUNTIME_PATCHES
  # "02-add-static-lib.patch"  # Not needed when BUILD_SHARED_LIB=OFF
  "03-fix-dll.patch"
  "04-fix-android-binary-size.patch"
  # "05-add-dependencies-to-config.patch"  # Only needed for shared library builds
  "06-fix-array-bounds-issue-ios-sim.patch"
  "11-fix-tpause-clang.patch"
)

# Add extra patches only for Windows builds
if("dml-ep" IN_LIST FEATURES)
  message(STATUS "Applying Windows-specific patches (DirectML)...")
  list(APPEND ONNXRUNTIME_PATCHES
    "07-fix-dml-export.patch"
    "12-fix-delayload-static-lib.patch"
  )
endif()

# Add extra patches only for Apple builds
if(VCPKG_CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR VCPKG_CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(STATUS "Applying Apple-specific patches (CoreML)...")
  list(APPEND ONNXRUNTIME_PATCHES
    "07-fix-coreml-export.patch"
    "08-fix-coreml-proto-include.patch"
    "13-fix-coreml-availability.patch"
  )
endif()

# Add extra patches only for Android builds
# Note: 07-fix-nnapi-export.patch is NOT needed for v1.24.2+ as EXPORT is already in the source
if(VCPKG_CMAKE_SYSTEM_NAME STREQUAL "Android" AND NOT "minimal-build" IN_LIST FEATURES)
  message(STATUS "Android build detected (NNAPI EP enabled via features)")
  # No additional patches needed for Android in v1.24.2+
endif()

# Add extra patches for XNNPack builds (TODO: as of v1.22.0, 10-fix-xnnpack-resize-empty-scales.patch is need. confirm if needed in future versions)
if("xnnpack-ep" IN_LIST FEATURES)
  message(STATUS "Applying XNNPack patches...")
  list(APPEND ONNXRUNTIME_PATCHES
    "07-fix-xnnpack-export.patch"
    "10-fix-xnnpack-resize-empty-scales.patch"
  )
endif()

if("minimal-build" IN_LIST FEATURES)
  list(APPEND ONNXRUNTIME_PATCHES
    "09-fix-minimal-build-onnx-onnx-proto-issue.patch"
  )
endif()

vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO microsoft/onnxruntime
  REF "v${VERSION}"
  SHA512 9f634692c0edb1910616c05b08e12ac20e393f637ca14d41fa46849dfd70a3719e1952af238fe862a2d77a3f0c66d03d1201b1739c85e193e102626413d6a041
  PATCHES ${ONNXRUNTIME_PATCHES}
)

# Apple build options
set(APPLE_BUILD_OPTIONS "")
if("coreml-ep" IN_LIST FEATURES AND
   (VCPKG_CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR VCPKG_CMAKE_SYSTEM_NAME STREQUAL "iOS"))
  message(STATUS "Pre-downloading coremltools for CoreML support...")

  vcpkg_download_distfile(COREMLTOOLS_ARCHIVE
    URLS "https://github.com/apple/coremltools/archive/refs/tags/7.1.zip"
    FILENAME "coremltools-7.1.zip"
    SHA512 c6645d0b48953fe4a7f3ffa34df35c40ddc764e76b9aa8ec1af282842f8346129df650514cb5bc6dde52ecb75750aac4ad159e5cfa6384146cfa72c75af77399
  )

  # Extract to the expected location for FetchContent
  set(DEPS_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/_deps")
  file(MAKE_DIRECTORY "${DEPS_DIR}")

  vcpkg_extract_source_archive_ex(
    OUT_SOURCE_PATH COREMLTOOLS_SOURCE_PATH
    ARCHIVE "${COREMLTOOLS_ARCHIVE}"
    WORKING_DIRECTORY "${DEPS_DIR}"
  )

  # Copy to the expected directory name
  set(COREMLTOOLS_DIR "${DEPS_DIR}/coremltools-src")
  file(REMOVE_RECURSE "${COREMLTOOLS_DIR}")
  file(COPY "${COREMLTOOLS_SOURCE_PATH}/" DESTINATION "${COREMLTOOLS_DIR}")

  # Verify proto files exist
  file(GLOB PROTO_FILES "${COREMLTOOLS_DIR}/mlmodel/format/*.proto")
  list(LENGTH PROTO_FILES PROTO_COUNT)
  message(STATUS "Found ${PROTO_COUNT} proto files in ${COREMLTOOLS_DIR}/mlmodel/format/")

  set(APPLE_BUILD_OPTIONS
    -Dcoremltools_SOURCE_DIR=${COREMLTOOLS_DIR}
    -Dcoremltools_POPULATED=TRUE
    -DFETCHCONTENT_FULLY_DISCONNECTED=OFF
  )
endif()

# Feature mapping
vcpkg_check_features(
  OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
      nnapi-ep onnxruntime_USE_NNAPI_BUILTIN
      coreml-ep onnxruntime_USE_COREML
      dml-ep onnxruntime_USE_DML
      xnnpack-ep onnxruntime_USE_XNNPACK
      minimal-build onnxruntime_MINIMAL_BUILD
      tests onnxruntime_BUILD_UNIT_TESTS
)

# Configure build
vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}/cmake"
  OPTIONS
    -Donnxruntime_USE_VCPKG=ON
    -Donnxruntime_BUILD_SHARED_LIB=OFF
    -Donnxruntime_ENABLE_BITCODE=OFF
    -Donnxruntime_ENABLE_PYTHON=OFF
    -Donnxruntime_DISABLE_RTTI=OFF
    -Donnxruntime_DISABLE_EXCEPTIONS=OFF
    ${FEATURE_OPTIONS}
    ${APPLE_BUILD_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_fixup_pkgconfig()

vcpkg_cmake_config_fixup(
  CONFIG_PATH lib/cmake/onnxruntime
)

# Fix: Add INTERFACE_INCLUDE_DIRECTORIES to the main onnxruntime target
set(CONFIG_FILE "${CURRENT_PACKAGES_DIR}/share/${PORT}/onnxruntimeTargets.cmake")
file(READ "${CONFIG_FILE}" _contents)
string(REPLACE
  "# Create imported target onnxruntime::onnxruntime\nadd_library(onnxruntime::onnxruntime INTERFACE IMPORTED)\n\nset_target_properties(onnxruntime::onnxruntime PROPERTIES\n  INTERFACE_LINK_LIBRARIES"
  "# Create imported target onnxruntime::onnxruntime\nadd_library(onnxruntime::onnxruntime INTERFACE IMPORTED)\n\nset_target_properties(onnxruntime::onnxruntime PROPERTIES\n  INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/include/onnxruntime\"\n  INTERFACE_LINK_LIBRARIES"
  _contents "${_contents}")
file(WRITE "${CONFIG_FILE}" "${_contents}")

# Fix: Change find_dependency(protobuf) to find_dependency(Protobuf) for case sensitivity
set(CONFIG_FILE "${CURRENT_PACKAGES_DIR}/share/${PORT}/onnxruntimeConfig.cmake")
file(READ "${CONFIG_FILE}" _contents)
string(REPLACE "find_dependency(protobuf)" "find_dependency(Protobuf)" _contents "${_contents}")
file(WRITE "${CONFIG_FILE}" "${_contents}")

# Cleanup
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

# Install copyright
vcpkg_install_copyright(FILE_LIST
  "${SOURCE_PATH}/LICENSE"
  "${SOURCE_PATH}/ThirdPartyNotices.txt"
)
