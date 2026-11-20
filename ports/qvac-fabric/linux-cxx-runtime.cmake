# Legacy builds share a static GNU ggml-base copy between CUDA and XDNA.
# The experimental mode imports the shared core and keeps only GNU runtime linkage.
function(qvac_configure_cxx_runtimes)
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
        return()
    endif()
    set(cuda_module OFF)
    if(TARGET ggml-cuda)
        get_target_property(cuda_type ggml-cuda TYPE)
        get_target_property(cuda_dir ggml-cuda SOURCE_DIR)
        get_directory_property(cuda_compiler_id DIRECTORY "${cuda_dir}"
            DEFINITION CMAKE_CUDA_COMPILER_ID)
        if(cuda_type STREQUAL "MODULE_LIBRARY" AND cuda_compiler_id STREQUAL "NVIDIA")
            set(cuda_module ON)
        endif()
    endif()
    set(xdna_module OFF)
    if(TARGET ggml-xdna)
        get_target_property(xdna_type ggml-xdna TYPE)
        if(xdna_type STREQUAL "MODULE_LIBRARY")
            set(xdna_module ON)
        endif()
    endif()
    if(NOT cuda_module AND NOT xdna_module)
        return()
    endif()

    if(NOT GGML_SHARED_CORE)
        get_target_property(base_dir ggml-base SOURCE_DIR)
        get_target_property(base_sources ggml-base SOURCES)
        set(stdcxx_base_sources)
        foreach(source IN LISTS base_sources)
            get_filename_component(source "${source}" ABSOLUTE BASE_DIR "${base_dir}")
            list(APPEND stdcxx_base_sources "${source}")
        endforeach()
        get_directory_property(base_definitions DIRECTORY "${base_dir}" COMPILE_DEFINITIONS)

        # Default visibility: the loader looks up the log functions in this core,
        # and a hidden symbol cannot be exported by the version script below.
        add_library(ggml-base-libstdcxx STATIC ${stdcxx_base_sources})
        set_target_properties(ggml-base-libstdcxx PROPERTIES POSITION_INDEPENDENT_CODE ON)
        target_compile_features(ggml-base-libstdcxx PRIVATE
            $<TARGET_PROPERTY:ggml-base,COMPILE_FEATURES>)
        target_include_directories(ggml-base-libstdcxx PRIVATE
            $<TARGET_PROPERTY:ggml-base,INCLUDE_DIRECTORIES>)
        target_include_directories(ggml-base-libstdcxx INTERFACE
            $<TARGET_PROPERTY:ggml-base,INTERFACE_INCLUDE_DIRECTORIES>)
        target_compile_definitions(ggml-base-libstdcxx PRIVATE
            $<TARGET_PROPERTY:ggml-base,COMPILE_DEFINITIONS>
            ${base_definitions})
        target_compile_definitions(ggml-base-libstdcxx INTERFACE
            $<TARGET_PROPERTY:ggml-base,INTERFACE_COMPILE_DEFINITIONS>)
        target_compile_options(ggml-base-libstdcxx PRIVATE
            $<TARGET_PROPERTY:ggml-base,COMPILE_OPTIONS>)
        target_link_libraries(ggml-base-libstdcxx PRIVATE
            $<TARGET_PROPERTY:ggml-base,LINK_LIBRARIES>)

    endif()

    set(stdcxx_targets)
    if(NOT GGML_SHARED_CORE)
        list(APPEND stdcxx_targets ggml-base-libstdcxx)
    endif()
    if(cuda_module)
        list(APPEND stdcxx_targets ggml-cuda)
        if(TARGET ggml-cuda-cutlass)
            list(APPEND stdcxx_targets ggml-cuda-cutlass)
        endif()
    endif()
    if(xdna_module)
        list(APPEND stdcxx_targets ggml-xdna ggml-cpu-xdna)
    endif()
    foreach(target IN LISTS stdcxx_targets)
        foreach(property LINK_LIBRARIES INTERFACE_LINK_LIBRARIES)
            get_target_property(libraries ${target} ${property})
            if(libraries AND NOT GGML_SHARED_CORE)
                list(TRANSFORM libraries REPLACE "^ggml-base$" "ggml-base-libstdcxx")
                list(TRANSFORM libraries REPLACE "^\\$<LINK_ONLY:ggml-base>$" "$<LINK_ONLY:ggml-base-libstdcxx>")
                set_property(TARGET ${target} PROPERTY ${property} ${libraries})
            endif()
        endforeach()
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            target_compile_options(${target} PRIVATE
                $<$<COMPILE_LANGUAGE:CXX>:-stdlib=libstdc++>
                $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=-stdlib=libstdc++>)
        endif()
    endforeach()
    set(modules)
    if(cuda_module)
        list(APPEND modules ggml-cuda)
    endif()
    if(xdna_module)
        list(APPEND modules ggml-xdna)
    endif()
    foreach(target IN LISTS modules)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            target_link_options(${target} PRIVATE -stdlib=libstdc++)
        endif()
        # Only backend entry points cross the module boundary. Legacy copies
        # also export logger hooks for forwarding between independent cores.
        set(exports "${CMAKE_CURRENT_BINARY_DIR}/${target}-exports.map")
        set(log_exports "ggml_log_set; ggml_log_get; ggml_log_callback_default;")
        if(GGML_SHARED_CORE)
            set(log_exports "")
        endif()
        file(WRITE "${exports}" "{\n  global: ggml_backend_init; ggml_backend_score;\n    ${log_exports}\n  local: *;\n};\n")
        set_property(TARGET ${target} APPEND PROPERTY LINK_DEPENDS "${exports}")
        target_link_options(${target} PRIVATE
            "LINKER:--version-script=${exports}" LINKER:-z,defs)
    endforeach()
    if(cuda_module)
        # The weak pure-virtual reference does not pull this from the archive.
        target_link_options(ggml-cuda PRIVATE
            -static-libstdc++ LINKER:--undefined=__cxa_pure_virtual
            LINKER:--as-needed)
        # CMake may append an implicit shared -lstdc++ for CUDA. Resolve the
        # runtime from its archive first, then discard the unused shared copy.
        if(GGML_SHARED_CORE)
            # Pull all GNU definitions in even when the earlier shared core
            # could satisfy an overlapping std/cxxabi symbol with libc++.
            target_link_libraries(ggml-cuda PRIVATE
                "-Wl,-Bstatic,--whole-archive" stdc++ "-Wl,--no-whole-archive,-Bdynamic")
        else()
            target_link_libraries(ggml-cuda PRIVATE
                "-Wl,-Bstatic" stdc++ "-Wl,-Bdynamic")
        endif()
    endif()
    if(xdna_module)
        # XRT exchanges C++ objects with this module and needs shared libstdc++.
        # Suppress the driver's implicit runtime, including the triplet's static
        # runtime option, and link the shared library explicitly.
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            target_link_options(ggml-xdna PRIVATE -nostdlib++)
        endif()
        if(GGML_SHARED_CORE)
            # Resolve the GNU C++ surface before considering the core's libc++.
            get_target_property(libraries ggml-xdna LINK_LIBRARIES)
            set_property(TARGET ggml-xdna PROPERTY LINK_LIBRARIES stdc++ ${libraries})
        else()
            target_link_libraries(ggml-xdna PRIVATE stdc++)
        endif()
        if(GGML_SHARED_CORE)
            set_target_properties(ggml-xdna PROPERTIES INSTALL_RPATH "$ORIGIN;${QVAC_XRT_ROOT}/lib")
        else()
            set_target_properties(ggml-xdna PROPERTIES INSTALL_RPATH "${QVAC_XRT_ROOT}/lib")
        endif()
    endif()
endfunction()

# Run after GGML has created and configured all backend targets.
cmake_language(DEFER CALL qvac_configure_cxx_runtimes)

if(GGML_SHARED_CORE)
    include("${CMAKE_CURRENT_LIST_DIR}/shared-core-runtime.cmake")
    cmake_language(DEFER CALL qvac_configure_shared_core_runtime)
endif()
