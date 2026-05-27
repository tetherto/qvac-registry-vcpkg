# tts-cpp: Resemble Chatterbox + Supertonic TTS in pure C++/ggml.
# Sourced from the tts-cpp/ subfolder of qvac-ext-lib-whisper.cpp;
# consumes the ggml-speech port.
#
# Pinned at tetherto/qvac-ext-lib-whisper.cpp@master HEAD 60dc1504
# (`Merge pull request #29 from GustavoA1604/master`), which lands
# 907f3151 -- the "tts-cpp: Add dynamic backend selection for android"
# change: registry-only `init_gpu_backend()` + Adreno tier policy
# + EngineOptions::backends_dir / opencl_cache_dir.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 60dc1504
    SHA512 2273e95bb7fa9a4db757f675627529094d8665baffc0c1c1783a65c7670222b779ae39667325fe870dccd92037faacb44502700e923bde73149eac08e6ab8eff
    HEAD_REF master
)

set(SOURCE_PATH "${WHISPER_CPP_SRC}/tts-cpp")
if (NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
    message(FATAL_ERROR
        "tts-cpp: ${SOURCE_PATH}/CMakeLists.txt missing; the tts-cpp/ "
        "subfolder layout in qvac-ext-lib-whisper.cpp may have changed.")
endif()

# The pinned tts-cpp CMakeLists.txt opportunistically links Accelerate on
# Apple hosts or any BLAS implementation found through CMake's FindBLAS on
# other hosts. That makes QVAC prebuilds inherit runner-specific dependencies
# such as libopenblas.so.0 without the port declaring or packaging them.
# Keep the registry build self-contained by removing that optional acceleration
# block until tts-cpp exposes a first-class option for it.
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt" [[
if (APPLE)
 find_library(TTS_CPP_ACCELERATE_FRAMEWORK Accelerate)
 if (TTS_CPP_ACCELERATE_FRAMEWORK)
 foreach(_tts_accel_target ${TTS_CPP_POINTWISE_ACCEL_TARGETS})
 if (TARGET ${_tts_accel_target})
 target_link_libraries(${_tts_accel_target} PRIVATE ${TTS_CPP_ACCELERATE_FRAMEWORK})
 target_compile_definitions(${_tts_accel_target} PRIVATE TTS_CPP_USE_ACCELERATE)
 endif()
 endforeach()
 endif()
else()
 check_include_file_cxx(cblas.h TTS_CPP_HAS_CBLAS_H)
 find_package(BLAS)
 if (TTS_CPP_HAS_CBLAS_H AND BLAS_FOUND)
 foreach(_tts_cblas_target ${TTS_CPP_POINTWISE_ACCEL_TARGETS})
 if (TARGET ${_tts_cblas_target})
 target_link_libraries(${_tts_cblas_target} PRIVATE ${BLAS_LIBRARIES})
 target_compile_definitions(${_tts_cblas_target} PRIVATE TTS_CPP_USE_CBLAS)
 endif()
 endforeach()
 endif()
endif()
]] [[
# QVAC registry builds intentionally do not auto-link host BLAS libraries.
]])

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
if("cuda" IN_LIST FEATURES)
    set(GGML_CUDA ON)
endif()
if("opencl" IN_LIST FEATURES)
    set(GGML_OPENCL ON)
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DTTS_CPP_BUILD_LIBRARY=ON
        -DTTS_CPP_BUILD_SHARED=OFF
        -DTTS_CPP_BUILD_EXECUTABLES=OFF
        -DTTS_CPP_BUILD_TESTS=OFF
        -DTTS_CPP_INSTALL=ON
        -DTTS_CPP_USE_SYSTEM_GGML=ON
        -DBUILD_SHARED_LIBS=OFF
        -DGGML_NATIVE=OFF
        -DGGML_OPENMP=OFF
        -DTTS_CPP_OPENMP=OFF
        -DGGML_CCACHE=OFF
        -DTTS_CPP_CCACHE=OFF
        -DGGML_METAL=${GGML_METAL}
        -DGGML_VULKAN=${GGML_VULKAN}
        -DGGML_CUDA=${GGML_CUDA}
        -DGGML_OPENCL=${GGML_OPENCL}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(PACKAGE_NAME tts-cpp CONFIG_PATH share/tts-cpp)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
