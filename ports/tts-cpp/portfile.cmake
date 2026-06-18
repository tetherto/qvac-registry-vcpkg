# tts-cpp: Resemble Chatterbox + Supertonic TTS in pure C++/ggml.
# Sourced from the tts-cpp/ subfolder of qvac-ext-lib-whisper.cpp;
# consumes the ggml-speech port.
#
# Pinned at tetherto/qvac-ext-lib-whisper.cpp@a7b36cbe
# (PR #43 QVAC-19557 chatterbox memory work, rebased onto master 40c95c6e —
# which already carries QVAC-19305 Supertonic v3 (PR #42), the per-sentence
# S3Gen streaming (QVAC-20484 PR #47), and QVAC-20556 Parakeet Mali-Vulkan
# (PR #51)).  PR #43 adds, on top of that base:
# - streamed GGUF tensor loads (no full-file host staging; removes the
#   +0.5..1 GB transient per chatterbox model load that jetsam-killed the
#   iOS SDK tests)
# - selectable chatterbox KV-cache dtype (EngineOptions::kv_cache_type =
#   f32|f16|q8_0) on a token-major KV slab; q8_0 stores the cache at ~27%
#   of f32 and decodes 20-30% faster on Metal, with a load-time capability
#   probe + F32 fallback and a Vulkan q8_0->f32 guard (coopmat2 FA fault)
# - removes the last direct ggml_backend_is_cpu / ggml_get_type_traits_cpu
#   references (routed via the backend registry + ggml_quantize_chunk),
#   keeping the static tts-cpp link safe under Android GGML_BACKEND_DL=ON.
#   This lets the qvac packages/tts-ggml temporary tts-cpp overlay be removed.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF a7b36cbed420574b385ea5ac5af0428634b9f872
    SHA512 04fbc7cbbc614bf6b49f2f742804f55912a844dd9e0c1fc8ccaa16097578e6712abf732d6e3cc74c48b8313c92a157f4ed25968932171cc9fad7bee1ba064ffd
    HEAD_REF master
)

set(SOURCE_PATH "${WHISPER_CPP_SRC}/tts-cpp")
if (NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
    message(FATAL_ERROR
        "tts-cpp: ${SOURCE_PATH}/CMakeLists.txt missing; the tts-cpp/ "
        "subfolder layout in qvac-ext-lib-whisper.cpp may have changed.")
endif()

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        metal   GGML_METAL
        vulkan  GGML_VULKAN
        cuda    GGML_CUDA
        opencl  GGML_OPENCL
)

set(PLATFORM_OPTIONS)

if(NOT VCPKG_TARGET_IS_OSX)
    list(APPEND PLATFORM_OPTIONS
        -DGGML_BLAS=OFF
        -DGGML_ACCELERATE=OFF
        -DCMAKE_DISABLE_FIND_PACKAGE_BLAS=ON
    )
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
        ${FEATURE_OPTIONS}
        ${PLATFORM_OPTIONS}
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
