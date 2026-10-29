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

# Server CUDA architectures (#141) and compatibility/fallback support (#130):
# https://github.com/tetherto/qvac-ext-ggml/pull/141
# https://github.com/tetherto/qvac-ext-ggml/pull/130
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tetherto/qvac-ext-ggml
    REF a4adfcb1304fb05b64473f1fe8d678bbce7a9ce0
    SHA512 15a7828668d60b2b630d906433370d792c597654af3ebcfe7c5b9121b563700db7074fb15934cf6d3ee55a4890bc48873c691b2ea2e5cb3d75e9ba412febdbc5
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

set(GGML_CUDA_OPTIONS "")

if("cuda" IN_LIST FEATURES)
    set(GGML_CUDA ON)
    include("${CMAKE_CURRENT_LIST_DIR}/cuda-toolkit.cmake")
    qvac_ggml_cuda_options(GGML_CUDA_OPTIONS)
endif()

if("opencl" IN_LIST FEATURES)
    set(GGML_OPENCL ON)
endif()

# --- Platform options ---
set(PLATFORM_OPTIONS)

if(VCPKG_TARGET_IS_LINUX AND GGML_CUDA)
    list(APPEND PLATFORM_OPTIONS
        "-DCMAKE_PROJECT_ggml_INCLUDE=${CMAKE_CURRENT_LIST_DIR}/linux-cuda-runtime.cmake"
    )
endif()

if(VCPKG_TARGET_IS_WINDOWS)
    list(APPEND PLATFORM_OPTIONS -DGGML_LTO=ON)
endif()

if(GGML_CUDA)
    # Keep the supported four FlashAttention combinations fixed. This fork's
    # CUDA graphs implementation is llama.cpp-only and is not used by diffusion.
    list(APPEND GGML_CUDA_OPTIONS
        -DGGML_CUDA_FA=ON
        -DGGML_CUDA_FA_ALL_QUANTS=OFF
        -DGGML_CUDA_GRAPHS=OFF)
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

# Hybrid backend mode for Android/Linux and Windows CUDA builds: GPU backends
# are runtime-loaded modules. The consuming
# addon carries no libvulkan.so.1 / libOpenCL.so NEEDED dependency, so it
# loads on hosts without any graphics stack (the GPU module simply fails to
# dlopen and ggml falls back to CPU).  The CPU backend is statically linked
# (GGML_CPU_STATIC) so that SD can call ggml_set_f32, ggml_backend_cpu_init,
# etc. directly at link time.
if(VCPKG_TARGET_IS_ANDROID OR VCPKG_TARGET_IS_LINUX OR (VCPKG_TARGET_IS_WINDOWS AND GGML_CUDA))
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
# the C++ runtime into the modules so they are self-contained. Non-CUDA modules
# match qvac-fabric's DL modules and the consuming addons. The
# module<->addon boundary is the C ggml-backend ABI. Vulkan uses libc++;
# linux-cuda-runtime.cmake gives nvcc and its private GGML core a static
# libstdc++ runtime instead. Android ships libc++_shared via the NDK STL.
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
        ${GGML_CUDA_OPTIONS}
        ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

# Keep runtime modules in lib/, matching qvac-fabric's package layout.
# Windows CMake exports still reference bin/, so retain that installed copy.
if(VCPKG_TARGET_IS_ANDROID OR VCPKG_TARGET_IS_LINUX OR (VCPKG_TARGET_IS_WINDOWS AND GGML_CUDA))
    set(backend_prefix "${VCPKG_TARGET_SHARED_LIBRARY_PREFIX}")
    set(backend_suffix "${VCPKG_TARGET_SHARED_LIBRARY_SUFFIX}")
    file(GLOB _backend_modules
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/bin/${backend_prefix}qvac-diffusion-ggml-*${backend_suffix}"
        "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/bin/Release/${backend_prefix}qvac-diffusion-ggml-*${backend_suffix}")
    if(_backend_modules)
        file(INSTALL ${_backend_modules} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()
endif()

if(VCPKG_TARGET_IS_WINDOWS AND GGML_CUDA)
    # These DLLs are plugins loaded at runtime, not shared dependencies of
    # the static core, and MODULE targets do not produce import libraries.
    set(VCPKG_POLICY_DLLS_IN_STATIC_LIBRARY enabled)
    set(VCPKG_POLICY_DLLS_WITHOUT_LIBS enabled)
    set(VCPKG_POLICY_ALLOW_DLLS_IN_LIB enabled)
endif()

# A missing CUDA module must never populate the CUDA feature's cache entry.
if(GGML_CUDA)
    set(cuda_module "${CURRENT_PACKAGES_DIR}/lib/${VCPKG_TARGET_SHARED_LIBRARY_PREFIX}qvac-diffusion-ggml-cuda${VCPKG_TARGET_SHARED_LIBRARY_SUFFIX}")
    if(NOT EXISTS "${cuda_module}")
        message(FATAL_ERROR "ggml: expected CUDA module was not installed at ${cuda_module}")
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

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
# The 2026-08-11 source tree ships no LICENSE file; install the fork's MIT
# text (unchanged from the previous REF) from the port instead.
vcpkg_install_copyright(FILE_LIST "${CMAKE_CURRENT_LIST_DIR}/LICENSE")
