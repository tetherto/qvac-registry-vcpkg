# tts-cpp: Resemble Chatterbox + Supertonic TTS in pure C++/ggml.
# Sourced from the tts-cpp/ subfolder of qvac-ext-lib-whisper.cpp;
# consumes the ggml-speech port.
#
# QVAC-21118 [TTS GGML] chunk-streaming CFM-step floor (qvac-ext-lib-whisper.cpp
# PR #62): for the Multilingual model (standard 10-step CFM) the chunk-streaming
# path floors a low stream_cfm_steps to the model's n_timesteps, fixing the
# saturation/clipping + per-chunk "wobble" that a meanflow-era low step count
# caused (the batch --cfm-steps knob and Turbo's meanflow 2-step sampler are
# untouched).
#
# Pinned at tetherto/qvac-ext-lib-whisper.cpp@master HEAD 1cc2d383 (PR #62
# merged).  Layered on the previous a679c7e7 pin (PR #43 merged):
# QVAC-19557 chatterbox iOS-memory work — streamed GGUF tensor loads (no
# full-file host staging), selectable chatterbox KV-cache dtype
# (EngineOptions::kv_cache_type = f32|f16|q8_0) on a token-major slab with a
# load-time capability probe + F32 fallback and a Vulkan q8_0->f32 guard.
#
# Layered on the previous b95ad447 pin (QVAC-19305 Supertonic v3 PR #42 base),
# which brought the two TTS-relevant master merges:
#   - QVAC-20616 [TTS GGML] end-of-speech robustness (PR #53): alignment-based
#     EOS stop (ports the AlignmentStreamAnalyzer cross-attention signal via an
#     in-graph attention probe) plus a heuristic stop controller (EOS
#     confidence, n-gram repetition, text-length budget) and per-language
#     calibration, so the Chatterbox multilingual model stops at end-of-
#     utterance instead of rambling for ~20s of random tokens past the text.
#   - QVAC-20557 Supertonic Android GPU (PR #54): Adreno OpenCL + Xclipse/Mali
#     Vulkan. This also reroutes Supertonic's direct CPU-backend calls that are
#     unlinkable under GGML_BACKEND_DL=ON --
#     ggml_get_type_traits_cpu()->from_float -> ggml_quantize_chunk()
#     (ggml-base, always linked) and ggml_backend_is_cpu() ->
#     tts_cpp::detail::backend_is_cpu() (registry shim) -- so the tts-ggml
#     addon dlopen's cleanly on Android. It is the upstream successor to the
#     f7d4d6c fix that the tts-ggml package-local overlay was carrying; with
#     this pin published, that overlay can be dropped.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 1cc2d383d5c3058533c5cd22b02270c68dc61d09
    SHA512 fcf9f78eab8df799234a017df77334ec133006062d436846deed243fef5e22908c5d6455bb8d9b8d767c6b193f6bb241cfeaed33ea1303cf4fa306a0ed38dd01
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
