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
#   share/ggml/      (CMake package config)
#
# GPU backend selection via vcpkg features:
#   metal  -> GGML_METAL=ON  (macOS/iOS, default-feature on Apple platforms)
#   vulkan -> GGML_VULKAN=ON
#   cuda   -> GGML_CUDA=ON
#   opencl -> GGML_OPENCL=ON

# Pulls from the tetherto/qvac-ext-ggml GitHub branch 2026-08-11
# (REF pinned to that branch's tip commit for reproducibility).
#
# e651f75 is based on the 2026-08-11 head and adds QVAC-23763 CUDA module
# selection and Windows dynamic backend support. It also includes the two
# QVAC-23767 fixes on top of f31dab0:
# - PR #61: cmake-only, skips the x86 cpu-feats OBJECT helper in hybrid
#   GGML_BACKEND_DL + GGML_CPU_STATIC builds, where the statically-linked CPU
#   backend never consults the DL variant score and the un-exported helper
#   broke install(EXPORT ggml-targets). Required for the desktop-Linux hybrid
#   mode below.
# - PR #64: drops a duplicated `case GGML_OP_POOL_2D` in the OpenCL backend
#   that made ggml-opencl fail to compile (Android is the only OpenCL
#   consumer in this family).
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tetherto/qvac-ext-ggml
    REF e651f757205359f35a683916c49b78b38308e920
    SHA512 808c73b85c464775b9f5a2da391db4e67a480aebbfbc12487d9a4d773362dc7d0cf66b0da51a06c1f7037f8c078d499173ed2a0783e359c50a48ad04c54b9d31
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
set(GGML_CUDA_OPTIONS)

if("cuda" IN_LIST FEATURES OR "cuda-jetson" IN_LIST FEATURES)
    set(GGML_CUDA ON)
    if("cuda" IN_LIST FEATURES AND "cuda-jetson" IN_LIST FEATURES)
        message(FATAL_ERROR "ggml: cuda and cuda-jetson must be built separately")
    endif()
    if("cuda-jetson" IN_LIST FEATURES)
        if(NOT (VCPKG_TARGET_IS_LINUX AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64"))
            message(FATAL_ERROR "ggml: cuda-jetson supports Linux arm64 only")
        endif()
        set(QVAC_CUDA_TOOLKIT "12.6.3-jetson")
        set(QVAC_CUDA_VERSION_PATTERN "V12\\.6\\.85([^0-9]|$)")
        set(QVAC_CUDA_ARCHS "87-real")
        list(APPEND GGML_CUDA_OPTIONS
            -DGGML_CUDA_NO_VMM=ON
            -DGGML_CUDA_MODULE_SUFFIX=-jetson)
    elseif(VCPKG_TARGET_IS_WINDOWS)
        if(NOT VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
            message(FATAL_ERROR "ggml: CUDA supports Windows x64 only")
        endif()
        set(QVAC_CUDA_TOOLKIT "13.0.3-server")
        set(QVAC_CUDA_VERSION_PATTERN "V13\\.0\\.88([^0-9]|$)")
        set(QVAC_CUDA_ARCHS "75-virtual\;80-virtual\;80-real\;86-real\;120a-real")
    elseif(VCPKG_TARGET_IS_LINUX)
        set(QVAC_CUDA_TOOLKIT "13.0.3-server")
        set(QVAC_CUDA_VERSION_PATTERN "V13\\.0\\.88([^0-9]|$)")
        if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
            set(QVAC_CUDA_ARCHS "80-virtual\;121-real")
        elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
            set(QVAC_CUDA_ARCHS "75-virtual\;80-virtual\;80-real\;86-real\;120a-real")
        else()
            message(FATAL_ERROR "ggml: CUDA supports Linux x64 and arm64 only")
        endif()
    else()
        message(FATAL_ERROR "ggml: CUDA supports Linux and Windows only")
    endif()

    if(DEFINED ENV{CUDACXX} AND EXISTS "$ENV{CUDACXX}")
        set(NVCC_EXECUTABLE "$ENV{CUDACXX}")
    endif()
    if(NOT NVCC_EXECUTABLE AND DEFINED ENV{CUDA_PATH})
        find_program(NVCC_EXECUTABLE nvcc PATHS "$ENV{CUDA_PATH}/bin" NO_DEFAULT_PATH)
    endif()
    if(NOT NVCC_EXECUTABLE)
        find_program(NVCC_EXECUTABLE nvcc)
    endif()
    if(NOT NVCC_EXECUTABLE)
        find_program(NVCC_EXECUTABLE nvcc PATHS /usr/local/cuda/bin NO_DEFAULT_PATH)
    endif()
    if(NOT NVCC_EXECUTABLE)
        message(FATAL_ERROR "ggml: CUDA feature needs a toolkit providing nvcc")
    endif()

    execute_process(
        COMMAND "${NVCC_EXECUTABLE}" --version
        RESULT_VARIABLE QVAC_NVCC_RESULT
        OUTPUT_VARIABLE QVAC_NVCC_VERSION
        ERROR_VARIABLE QVAC_NVCC_ERROR)
    if(NOT QVAC_NVCC_RESULT EQUAL 0 OR NOT QVAC_NVCC_VERSION MATCHES "${QVAC_CUDA_VERSION_PATTERN}")
        message(FATAL_ERROR "ggml: ${QVAC_CUDA_TOOLKIT} is required, but ${NVCC_EXECUTABLE} reported: ${QVAC_NVCC_VERSION}${QVAC_NVCC_ERROR}")
    endif()

    set(GGML_CUDA_COMPILER_OPTION "-DCMAKE_CUDA_COMPILER=${NVCC_EXECUTABLE}")
    list(APPEND GGML_CUDA_OPTIONS "-DCMAKE_CUDA_ARCHITECTURES=${QVAC_CUDA_ARCHS}")
    if(VCPKG_TARGET_IS_LINUX)
        list(APPEND GGML_CUDA_OPTIONS
            -DCMAKE_CUDA_HOST_COMPILER=clang++
            "-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler")
    endif()
    message(STATUS "CUDA compiler: ${NVCC_EXECUTABLE}; toolkit: ${QVAC_CUDA_TOOLKIT}; archs: ${QVAC_CUDA_ARCHS}")
endif()

if("opencl" IN_LIST FEATURES)
    set(GGML_OPENCL ON)
endif()

# --- Platform options ---
set(PLATFORM_OPTIONS)

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

# Hybrid backend mode for Android and desktop Linux: GPU backends (Vulkan,
# OpenCL) are MODULE .so files loaded at runtime via dlopen - the consuming
# addon carries no libvulkan.so.1 / libOpenCL.so NEEDED dependency, so it
# loads on hosts without any graphics stack (the GPU module simply fails to
# dlopen and ggml falls back to CPU).  The CPU backend is statically linked
# (GGML_CPU_STATIC) so that SD can call ggml_set_f32, ggml_backend_cpu_init,
# etc. directly at link time.
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
        ${GGML_CUDA_OPTIONS}
        ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

# The pinned source installs every DL module through its CMake install rules.
# Fail here if a requested CUDA module was not produced or installed.
if("cuda-jetson" IN_LIST FEATURES)
    set(QVAC_EXPECTED_CUDA_MODULE "${CURRENT_PACKAGES_DIR}/lib/libqvac-diffusion-ggml-cuda-jetson.so")
elseif("cuda" IN_LIST FEATURES)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(QVAC_EXPECTED_CUDA_MODULE "${CURRENT_PACKAGES_DIR}/lib/qvac-diffusion-ggml-cuda.dll")
    else()
        set(QVAC_EXPECTED_CUDA_MODULE "${CURRENT_PACKAGES_DIR}/lib/libqvac-diffusion-ggml-cuda.so")
    endif()
endif()
if(DEFINED QVAC_EXPECTED_CUDA_MODULE AND NOT EXISTS "${QVAC_EXPECTED_CUDA_MODULE}")
    message(FATAL_ERROR "ggml: expected CUDA module was not installed: ${QVAC_EXPECTED_CUDA_MODULE}")
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

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
# The 2026-08-11 source tree ships no LICENSE file; install the fork's MIT
# text (unchanged from the previous REF) from the port instead.
vcpkg_install_copyright(FILE_LIST "${CMAKE_CURRENT_LIST_DIR}/LICENSE")
