vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO tetherto/qvac-ext-lib-whisper.cpp
  REF f3102199642e78bb2beee6b9e9537604009148b9
  SHA512 64b102677abae7825985c946b1103cdaefc3f0d0d64f54dbdc5b38ee38a92efd553d33ed5a9f7aa5e509b0292478d8a93dbc8fd54dae7811b84a41d07f4b1c5c
  HEAD_REF master
)

if (VCPKG_TARGET_IS_ANDROID)
  # NDK only comes with C headers.
  # Make sure C++ header exists, it will be used by ggml tensor library.
  # Need to determine installed vulkan version and download correct headers
  include(${CMAKE_CURRENT_LIST_DIR}/android-vulkan-version.cmake)
  detect_ndk_vulkan_version()
  message(STATUS "Using Vulkan C++ wrappers from version: ${vulkan_version}")
  file(DOWNLOAD
    "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v${vulkan_version}.tar.gz"
    "${SOURCE_PATH}/vulkan-sdk-${vulkan_version}.tar.gz"
    TLS_VERIFY ON
  )

  file(ARCHIVE_EXTRACT
    INPUT "${SOURCE_PATH}/vulkan-sdk-${vulkan_version}.tar.gz"
    DESTINATION "${SOURCE_PATH}"
  )

  # Copy the Vulkan headers to where the build system expects them
  # The build system looks for vulkan/vulkan.hpp with include path pointing to ggml/src/
  file(COPY "${SOURCE_PATH}/Vulkan-Headers-${vulkan_version}/include/"
       DESTINATION "${SOURCE_PATH}/ggml/src/")
  
  # Clean up the temporary extracted directory
  file(REMOVE_RECURSE "${SOURCE_PATH}/Vulkan-Headers-${vulkan_version}")
endif()

set(PLATFORM_OPTIONS)

if (VCPKG_TARGET_IS_OSX)
  list(APPEND PLATFORM_OPTIONS -DGGML_METAL=ON)
elseif (VCPKG_TARGET_IS_IOS)
  # Intentionally NOT -DGGML_METAL=ON. iOS bare-kit builds were hitting
  # a separate Metal/Compiler XPC crash during transcribe() on physical
  # iPhone (XPC_ERROR_CONNECTION_INTERRUPTED / MTLCompiler peer-unloaded)
  # that is being investigated independently of the OutputCallBackJs
  # teardown UAF. Force the flag OFF so it overrides any upstream default
  # and stays explicit in the build log; iOS falls back to the CPU
  # backend until the Metal-side issue is fixed.
  list(APPEND PLATFORM_OPTIONS -DGGML_METAL=OFF)
elseif("vulkan" IN_LIST FEATURES)
  list(APPEND PLATFORM_OPTIONS -DGGML_VULKAN=ON)
else()
  list(APPEND PLATFORM_OPTIONS -DGGML_VULKAN=OFF)
endif()

# Android: ship the same dynamic-backend + CPU-variant recipe llama-cpp
# already uses on this triplet. GGML_BACKEND_DL=ON makes ggml load the
# backend implementations as separate .so files at runtime (one per
# backend, picked by the device caps), so a single APK ships all the
# variants and the consumer's binary only statically links the dispatcher.
# GGML_CPU_ALL_VARIANTS + GGML_CPU_REPACK gives one tuned CPU .so per
# microarch (armv8.0/armv8.2-fp16/armv8.2-fp16+dotprod/armv8.7-i8mm), and
# COOPMAT[2] are disabled because the Vulkan validation layer's coopmat
# extensions are unstable on Adreno NDK headers.
# OpenCL is gated behind the `opencl` feature so non-Adreno Android
# consumers don't pull in an unused backend.
# Android dynamic-backend mode: per-microarch CPU + GPU backends ship as
# MODULE .so files dlopen'd at runtime, while the dispatcher
# (libwhisper.a, libggml.a, libggml-base.a) stays static — same shape
# as the speech-stack uses for parakeet-cpp/tts-cpp.
#
# The bundled ggml in this port's REF pin carries two commits from
# QVAC-18993 that make the combo above work end-to-end on Android:
#   eb63b2b7  ggml : allow GGML_BACKEND_DL with a static core
#             (removes the FATAL_ERROR + flips PIC/GGML_BUILD on)
#   3683de4b  ggml-backend : android per-arch CPU variant dlopen fallback
#             (lets ggml_backend_load_best resolve libggml-cpu-android_armv*_*.so
#              via Android's in-APK linker when there's no on-disk lib dir)
# Both will land on tetherto/master via whisper-cpp PR #26 (QVAC-18993);
# after that ships + a v1.8.4.3 tag is published, the port can re-point
# to tetherto + drop the temporary Zbig9000 pin above.
if(VCPKG_TARGET_IS_ANDROID)
  set(DL_BACKENDS ON)
  list(APPEND PLATFORM_OPTIONS
    -DGGML_BACKEND_DL=ON
    -DGGML_CPU_ALL_VARIANTS=ON
    -DGGML_CPU_REPACK=ON
    -DGGML_VULKAN_DISABLE_COOPMAT=ON
    -DGGML_VULKAN_DISABLE_COOPMAT2=ON)
  if("opencl" IN_LIST FEATURES)
    list(APPEND PLATFORM_OPTIONS -DGGML_OPENCL=ON)
  endif()
else()
  set(DL_BACKENDS OFF)
endif()

# spirv-headers include-shim: upstream ggml uses spv::* enums
# unconditionally in ggml-vulkan.cpp, and ggml-vulkan's CMakeLists.txt
# does not call find_package(SpirvHeaders), so the vcpkg-installed
# include prefix is not visible to it by default.
#
# Append to VCPKG_C_FLAGS / VCPKG_CXX_FLAGS (same shape as qvac-fabric's
# portfile, ref qvac-registry-vcpkg commit db03cfc8) so the include path
# is merged with the triplet-supplied flags (-fPIC, -stdlib=libc++ on
# Linux, etc.). The previous form passed -DCMAKE_CXX_FLAGS=... via
# vcpkg_cmake_configure OPTIONS, which is a CMake cache-variable
# override that clobbered the triplet flags wholesale and produced
# libstdc++/libc++ ABI mismatches at link time for consumers that
# target libc++.
#
# MSVC's cl.exe does not understand `-isystem` (it treats the flag as a
# positional source file argument and tries to compile the include
# path), so use `/I` there and the GCC/Clang `-isystem` form elsewhere.
if("vulkan" IN_LIST FEATURES)
  if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    string(APPEND VCPKG_C_FLAGS " /I${CURRENT_INSTALLED_DIR}/include")
    string(APPEND VCPKG_CXX_FLAGS " /I${CURRENT_INSTALLED_DIR}/include")
  else()
    string(APPEND VCPKG_C_FLAGS " -isystem ${CURRENT_INSTALLED_DIR}/include")
    string(APPEND VCPKG_CXX_FLAGS " -isystem ${CURRENT_INSTALLED_DIR}/include")
  endif()
endif()

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
  OPTIONS
    -DGGML_CCACHE=OFF
    -DGGML_OPENMP=OFF
    -DGGML_NATIVE=OFF
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_BUILD_EXAMPLES=OFF
    -DWHISPER_BUILD_SERVER=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DGGML_BUILD_NUMBER=1
    ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(
  PACKAGE_NAME whisper
  CONFIG_PATH share/whisper
)

vcpkg_fixup_pkgconfig()

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (NOT DL_BACKENDS AND VCPKG_LIBRARY_LINKAGE MATCHES "static")
  # On dynamic-backend Android the ggml backend .so files live in bin/
  # alongside the static dispatcher; wiping bin/ here would silently
  # ship a runtime that loads no backends. Only wipe for true
  # static-only triplets.
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")