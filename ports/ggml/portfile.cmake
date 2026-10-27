# ggml vcpkg overlay port
#
# Builds the ggml tensor library from tetherto/qvac-ext-ggml for the QVAC
# diffusion stack (paired with the stable-diffusion-cpp port from the same
# branch date).
#
# Installed artefacts:
#   include/ggml.h  (+ other ggml public headers)
#   lib/libggml.a, lib/libggml-base.a, lib/libggml-cpu.a, ...
#   lib/libqvac-diffusion-ggml-*.so  (dlopen'd GPU backend modules, see below)
#   lib/qvac-diffusion-ggml-*.dll    (the same modules on Windows)
#   share/ggml/      (CMake package config)
#
# GPU backend selection via vcpkg features:
#   metal  -> GGML_METAL=ON  (macOS/iOS, default-feature on Apple platforms)
#   vulkan -> GGML_VULKAN=ON
#   cuda   -> GGML_CUDA=ON
#   opencl -> GGML_OPENCL=ON

# Windows backend modules against a static ggml core (QVAC-25560), on top of
# the CUDA device compatibility and backend fallback work from
# https://github.com/tetherto/qvac-ext-ggml/pull/130
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tetherto/qvac-ext-ggml
    REF a98582045925ca61fe908d60eabbae3c62238cad
    SHA512 92d2d75a54fc0436c0c16f8670f36c52a40cc361583f1bb722154e09d2a4c2ac6b371e797079de072035058d4a634b26e36ca9560c89558632419f3ee8ee5f2a
)

# --- GPU feature flags ---
set(GGML_METAL  OFF)
set(GGML_VULKAN OFF)
set(GGML_CUDA   OFF)
set(GGML_OPENCL OFF)

if("metal" IN_LIST FEATURES)
    set(GGML_METAL ON)
endif()

if("vulkan" IN_LIST FEATURES)
    set(GGML_VULKAN ON)
endif()

set(GGML_CUDA_COMPILER_OPTION "")

if("cuda" IN_LIST FEATURES)
    set(GGML_CUDA ON)
    # Locate nvcc explicitly - /usr/local/cuda/bin may not be on the PATH that
    # vcpkg's isolated cmake process inherits.
    find_program(NVCC_EXECUTABLE nvcc
        PATHS /usr/local/cuda/bin /usr/local/cuda-12.8/bin
        NO_DEFAULT_PATH
    )
    if(NOT NVCC_EXECUTABLE)
        find_program(NVCC_EXECUTABLE nvcc REQUIRED)
    endif()
    set(GGML_CUDA_COMPILER_OPTION "-DCMAKE_CUDA_COMPILER=${NVCC_EXECUTABLE}")
    message(STATUS "CUDA compiler: ${NVCC_EXECUTABLE}")
endif()

if("opencl" IN_LIST FEATURES)
    set(GGML_OPENCL ON)
endif()

# --- Platform options ---
set(PLATFORM_OPTIONS)

if(VCPKG_TARGET_IS_WINDOWS)
    list(APPEND PLATFORM_OPTIONS -DGGML_LTO=ON)
endif()

if(VCPKG_TARGET_IS_IOS)
    list(APPEND PLATFORM_OPTIONS -DGGML_BLAS=OFF -DGGML_ACCELERATE=OFF)
endif()

# --- Android: allow the pinned Vulkan C++ / SPIRV header fetch ---
# The NDK ships only the C Vulkan headers; the 2026-08-11 ggml fetches pinned
# header-only copies of Vulkan-Headers and SPIRV-Headers itself via
# FetchContent (src/ggml-vulkan/CMakeLists.txt, `if (ANDROID)` block). The
# registry vcpkg-cmake sets FETCHCONTENT_FULLY_DISCONNECTED=ON globally, so
# allow the fetch here (same pattern as the qvac-fabric port).
if(VCPKG_TARGET_IS_ANDROID AND "vulkan" IN_LIST FEATURES)
    list(APPEND PLATFORM_OPTIONS -DFETCHCONTENT_FULLY_DISCONNECTED=OFF)
endif()

# Hybrid backend mode for Android, desktop Linux and Windows: GPU backends
# (Vulkan, OpenCL) are MODULE .so / .dll files loaded at runtime via dlopen or
# LoadLibrary - the consuming addon carries no libvulkan.so.1 / libOpenCL.so /
# vulkan-1.dll import, so it loads on hosts without any graphics stack (the
# GPU module simply fails to load and ggml falls back to CPU).  The CPU
# backend is statically linked (GGML_CPU_STATIC) so that SD can call
# ggml_set_f32, ggml_backend_cpu_init, etc. directly at link time.
if(VCPKG_TARGET_IS_ANDROID OR VCPKG_TARGET_IS_LINUX OR VCPKG_TARGET_IS_WINDOWS)
    list(APPEND PLATFORM_OPTIONS
        -DGGML_BACKEND_DL=ON
        -DGGML_CPU_STATIC=ON
    )
endif()

# Adreno-specific coopmat workarounds stay Android-only; desktop Vulkan keeps
# coopmat, matching the previous statically-linked desktop builds.
if(VCPKG_TARGET_IS_ANDROID)
    list(APPEND PLATFORM_OPTIONS
        -DGGML_VULKAN_DISABLE_COOPMAT=ON
        -DGGML_VULKAN_DISABLE_COOPMAT2=ON
    )
endif()

# The desktop-Linux triplets build with -stdlib=libc++.  Backend MODULE .so
# files are dlopen'd on end-user machines that may not have libc++ installed
# (e.g. stock ubuntu-24.04), where an unresolved libc++.so.1 NEEDED makes the
# dlopen fail silently and the GPU backend never registers.  Statically link
# the C++ runtime into the modules so they are self-contained, matching
# qvac-fabric's DL modules and how the consuming addons link themselves.  The
# module<->addon boundary is the C ggml-backend ABI, so per-module libc++
# copies never exchange C++ objects.  Android ships libc++_shared via the NDK
# STL instead.
if(VCPKG_TARGET_IS_LINUX)
    string(APPEND VCPKG_LINKER_FLAGS " -static-libstdc++")
endif()

# --- Configure & build ---
# Only build Release, matching the release-only consumers in this package
# family.
set(VCPKG_BUILD_TYPE release)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBUILD_SHARED_LIBS=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DGGML_NATIVE=OFF
        -DGGML_CCACHE=OFF
        -DGGML_OPENMP=OFF
        -DGGML_LLAMAFILE=OFF
        -DGGML_BUILD_TESTS=OFF
        -DGGML_BUILD_EXAMPLES=OFF
        -DGGML_METAL=${GGML_METAL}
        -DGGML_VULKAN=${GGML_VULKAN}
        -DGGML_CUDA=${GGML_CUDA}
        -DGGML_OPENCL=${GGML_OPENCL}
        -DGGML_MAX_NAME=128  # stable-diffusion.cpp requires >= 128
        ${GGML_CUDA_COMPILER_OPTION}
        ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

# Windows DL backend pickup: cmake install() puts the MODULE .dll files in
# bin/, but the consuming addon stages backends from a lib/ glob, and a
# static-linkage triplet must not ship a bin/ directory.  Move them.
if(VCPKG_TARGET_IS_WINDOWS)
    file(GLOB _backend_dlls "${CURRENT_PACKAGES_DIR}/bin/qvac-diffusion-ggml-*.dll")
    foreach(_dll IN LISTS _backend_dlls)
        get_filename_component(_dll_name "${_dll}" NAME)
        file(RENAME "${_dll}" "${CURRENT_PACKAGES_DIR}/lib/${_dll_name}")
    endforeach()
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin"
                        "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

# Install DL backend .so files for Android and desktop Linux.  ggml builds
# each backend as a MODULE target but does NOT install them via cmake
# install().
if(VCPKG_TARGET_IS_ANDROID OR VCPKG_TARGET_IS_LINUX)
    file(GLOB _backend_sos
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/bin/libqvac-diffusion-ggml-*.so"
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/bin/libqvac-ggml-*.so"
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/bin/libggml-*.so"
    )
    if(_backend_sos)
        file(INSTALL ${_backend_sos} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()
endif()

# Fix up the CMake package config installed by ggml's own build system.
vcpkg_cmake_config_fixup(PACKAGE_NAME ggml CONFIG_PATH share/ggml)

# ggml installs a .pc to share/pkgconfig; move it to lib/pkgconfig and fix
# absolute paths so vcpkg's post-build checks pass.
if(EXISTS "${CURRENT_PACKAGES_DIR}/share/pkgconfig/ggml.pc")
    file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/lib/pkgconfig")
    file(RENAME "${CURRENT_PACKAGES_DIR}/share/pkgconfig/ggml.pc"
                "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/ggml.pc")
endif()
if(EXISTS "${CURRENT_PACKAGES_DIR}/debug/share/pkgconfig/ggml.pc")
    file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig")
    file(RENAME "${CURRENT_PACKAGES_DIR}/debug/share/pkgconfig/ggml.pc"
                "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/ggml.pc")
endif()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/share/pkgconfig"
                    "${CURRENT_PACKAGES_DIR}/debug/share/pkgconfig")
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

# DL backends are only built for release; debug build produces fewer binaries.
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
if(VCPKG_TARGET_IS_WINDOWS)
    # The runtime-loaded backend DLLs are payload of a static-linkage port,
    # not linked libraries; without this the static-build post-build check
    # rejects them.
    set(VCPKG_POLICY_DLLS_IN_STATIC_LIBRARY enabled)
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
# The 2026-08-11 source tree ships no LICENSE file; install the fork's MIT
# text (unchanged from the previous REF) from the port instead.
vcpkg_install_copyright(FILE_LIST "${CMAKE_CURRENT_LIST_DIR}/LICENSE")
