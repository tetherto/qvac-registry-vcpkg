vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-marian-dev
  REF da6ff8fd
  SHA512 383fd6e9b108f3cbfa3cf3ce431894da7bb9f2a8e5bc1627e222aa829179f0a40af07b6ada3f4b780004d3320fa026fd4e7da69ad91134569ab3192a49835df4
)

set(_BUILD_ARCH_OPT "")
if(VCPKG_TARGET_IS_ANDROID)
    if(VCPKG_TARGET_ARCHITECTURE MATCHES "arm64|ARM64|aarch64")
    set(_BUILD_ARCH_OPT "-DBUILD_ARCH=armv8-a")
  endif()
endif()

if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
  if(VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_OSX OR VCPKG_TARGET_IS_IOS)
    set(_BUILD_ARCH_OPT "-DBUILD_ARCH=x86-64-v2")
  endif()
endif()

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
  OPTIONS
    -DCOMPILE_CPU=ON
    -DCOMPILE_CUDA=OFF
    -DCOMPILE_EXAMPLES=OFF
    -DCOMPILE_SERVER=OFF
    -DCOMPILE_TESTS=OFF
    -DUSE_CCACHE=OFF
    -DUSE_CUDNN=OFF
    -DUSE_DOXYGEN=OFF
    -DUSE_FBGEMM=OFF
    -DUSE_MPI=OFF
    -DUSE_NCCL=OFF
    -DUSE_ONNX=OFF
    -DUSE_SENTENCEPIECE=ON
    -DUSE_EXTERNAL_SENTENCEPIECE=ON
    -DUSE_STATIC_LIBS=ON
    -DCOMPILE_WASM=OFF
    -DUSE_WASM_COMPATIBLE_SOURCE=OFF
    -DGENERATE_MARIAN_INSTALL_TARGETS=ON
    ${_BUILD_ARCH_OPT}
)

vcpkg_cmake_build()
vcpkg_cmake_install()

vcpkg_cmake_config_fixup(
  PACKAGE_NAME marian
  CONFIG_PATH lib/cmake/marian
)

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/marian-devConfig.cmake" [=[
get_filename_component(PACKAGE_PREFIX_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
include("${PACKAGE_PREFIX_DIR}/share/marian/marianConfig.cmake")
if(TARGET marian::marian AND NOT TARGET marian-dev::marian-dev)
  add_library(marian-dev::marian-dev ALIAS marian::marian)
endif()
]=])

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.md")
