vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-marian-dev
  # da6ff8fd + QVAC-28896: createLoggers() no longer installs std::terminate and
  # SIGSEGV/SIGFPE handlers unless marian::setInstallErrorHandlers(true) is called,
  # so a host process (a JVM, for one) keeps its own signal handlers.
  REF 73b90b27b43bffdc2e6ccecfe42500ede55bcff3
  SHA512 ad5f497106c7fc011fa54ebd2945b1ec474bc9450433437c65aba90a2790b3e1c3db7be100804354443f3e29f2926295c991c5e0e8e1fee234989a3f7e2f9273
)

# Marian defaults to `set(BUILD_ARCH native CACHE STRING ...)` and splices it
# into CMAKE_CXX_FLAGS as `-march=${BUILD_ARCH}`. Left at that default the
# compiler targets whatever CPU the builder happens to have and emits those
# extensions inline with no runtime dispatch, so the artifact faults with
# SIGILL on any lesser CPU. Every platform we ship needs an explicit floor.
#
# BUILD_ARCH is the only lever that works: marian appends to CMAKE_CXX_FLAGS
# but puts its own `-march=${BUILD_ARCH}` last, so an -march passed through
# VCPKG_CXX_FLAGS is overridden by it. On AArch64 nothing else changes -- the
# INTRINSICS block that a non-native BUILD_ARCH selects is x86-gated.
set(_BUILD_ARCH_OPT "")
if(VCPKG_TARGET_ARCHITECTURE MATCHES "arm64|ARM64|aarch64")
  # ARMv8.0-A is the only coherent AArch64 floor: SVE is optional at every
  # level below ARMv9 (absent on Cortex-A72/A76/A78, Neoverse N1, Ampere
  # Altra), so a higher baseline would still need an explicit +nosve.
  #
  # Trade-off: without +lse, atomics compile to ldxr/stxr exclusive loops
  # rather than LSE. Marian's atomic traffic is in model construction and
  # config paths, not inference inner loops, so this is not on a hot path.
  # If it ever needs recovering, add -moutline-atomics (runtime-dispatched);
  # it is NOT a clang default and must be passed explicitly.
  # See https://github.com/tetherto/qvac/issues/3364.
  if(VCPKG_TARGET_IS_ANDROID OR VCPKG_TARGET_IS_LINUX)
    set(_BUILD_ARCH_OPT "-DBUILD_ARCH=armv8-a")
  endif()
elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
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
