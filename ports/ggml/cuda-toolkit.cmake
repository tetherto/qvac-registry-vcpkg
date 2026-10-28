# Server CUDA build contract, shared with qvac-fabric's CUDA 13 package.
function(qvac_ggml_cuda_options out_options)
    set(expected_nvcc "13.0.88")
    set(expected_toolkit "13.0.3-server")
    # Match qvac-fabric's packaged CUDA 13 targets. ARM64 ships only Spark
    # to keep the npm platform package within its size limit.
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(archs "121a-real")
        set(minimum_cuda "12.9")
    else()
        set(archs "75-virtual;80-real;86-real;89-real;90-virtual;120a-real")
        set(minimum_cuda "12.8")
    endif()

    if(NOT "$ENV{QVAC_CUDA_TOOLKIT}" STREQUAL "" AND
       NOT "$ENV{QVAC_CUDA_TOOLKIT}" STREQUAL "${expected_toolkit}")
        message(FATAL_ERROR "ggml: toolkit identity '$ENV{QVAC_CUDA_TOOLKIT}' does not match ${expected_toolkit}")
    endif()

    # A provisioned compiler wins over the system installation. Do not reuse
    # find_program's cache when a different toolkit is selected on the next run.
    unset(nvcc)
    unset(nvcc CACHE)
    if(NOT "$ENV{CUDACXX}" STREQUAL "")
        set(nvcc "$ENV{CUDACXX}")
    elseif(NOT "$ENV{CUDA_PATH}" STREQUAL "")
        find_program(nvcc NAMES nvcc PATHS "$ENV{CUDA_PATH}/bin"
            NO_DEFAULT_PATH NO_CACHE REQUIRED)
    else()
        # Preserve /usr/local/cuda preference for ordinary source builds.
        find_program(nvcc NAMES nvcc PATHS /usr/local/cuda/bin
            NO_DEFAULT_PATH NO_CACHE)
        if(NOT nvcc)
            find_program(nvcc NAMES nvcc NO_CACHE REQUIRED)
        endif()
    endif()
    execute_process(COMMAND "${nvcc}" --version
        RESULT_VARIABLE result OUTPUT_VARIABLE version_out ERROR_VARIABLE version_err)
    if(NOT result STREQUAL "0")
        message(FATAL_ERROR "ggml: cannot query nvcc ${nvcc}: ${result} ${version_err}")
    endif()
    string(REGEX MATCH "V([0-9]+\\.[0-9]+\\.[0-9]+)" match "${version_out}")
    if(NOT match)
        message(FATAL_ERROR "ggml: cannot parse nvcc version: ${version_out}")
    endif()
    set(actual_nvcc "${CMAKE_MATCH_1}")
    if(NOT actual_nvcc VERSION_EQUAL expected_nvcc)
        if(NOT "$ENV{QVAC_CUDA_TOOLKIT}" STREQUAL "")
            message(FATAL_ERROR "ggml: ${nvcc} is CUDA ${actual_nvcc}, expected ${expected_nvcc}")
        endif()
        if(actual_nvcc VERSION_LESS minimum_cuda)
            message(FATAL_ERROR "ggml: ${VCPKG_TARGET_ARCHITECTURE} server architectures require CUDA ${minimum_cuda} or newer")
        endif()
        message(WARNING "ggml: unpinned local CUDA ${actual_nvcc}; release builds require ${expected_nvcc}. Not for release builds.")
    endif()

    # ggml calls find_package(CUDAToolkit) before enable_language(CUDA), so
    # keep library/header discovery on the same toolkit as the selected nvcc.
    get_filename_component(cuda_bin "${nvcc}" DIRECTORY)
    get_filename_component(cuda_root "${cuda_bin}" DIRECTORY)
    message(STATUS "ggml CUDA: compiler=${nvcc}, version=${actual_nvcc}, architectures=${archs}")
    string(REPLACE ";" "\\;" escaped_archs "${archs}")
    set(options
        "-DCMAKE_CUDA_COMPILER=${nvcc}"
        "-DCUDAToolkit_ROOT=${cuda_root}"
        "-DCMAKE_CUDA_ARCHITECTURES=${escaped_archs}")
    set(${out_options} "${options}" PARENT_SCOPE)
endfunction()
