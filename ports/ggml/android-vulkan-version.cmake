# Detect the Vulkan version shipped with the Android NDK by parsing
# vulkan_core.h from the NDK sysroot. Sets `vulkan_version` and
# `vulkan_headers_sha512` in the caller's scope.
function(detect_ndk_vulkan_version)
    string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}" host_system_name_lower)

    file(GLOB host_dirs LIST_DIRECTORIES true "$ENV{ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${host_system_name_lower}-*")
    if(host_dirs)
        list(GET host_dirs 0 host_dir)
        get_filename_component(host_arch "${host_dir}" NAME)
        set(vulkan_core_h "$ENV{ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${host_arch}/sysroot/usr/include/vulkan/vulkan_core.h")
    else()
        message(FATAL_ERROR "Could not find NDK host directory for ${host_system_name_lower}")
    endif()

    if(NOT EXISTS "${vulkan_core_h}")
        message(FATAL_ERROR "vulkan_core.h not found at ${vulkan_core_h}")
    endif()

    file(READ "${vulkan_core_h}" header_content)
    string(REGEX MATCH "VK_HEADER_VERSION ([0-9]+)" version_match "${header_content}")
    if(version_match)
        set(header_version_3 "${CMAKE_MATCH_1}")
    else()
        message(FATAL_ERROR "Could not extract VK_HEADER_VERSION from ${vulkan_core_h}")
    endif()

    # Extract major.minor version from VK_HEADER_VERSION_COMPLETE for download URL
    string(REGEX MATCH "VK_HEADER_VERSION_COMPLETE VK_MAKE_API_VERSION\\(([0-9]+), ([0-9]+), ([0-9]+)" version_match "${header_content}")
    if(version_match)
        set(major "${CMAKE_MATCH_2}")
        set(minor "${CMAKE_MATCH_3}")
        set(vulkan_version "${major}.${minor}.${header_version_3}")
    else()
        message(FATAL_ERROR "Could not extract VK_HEADER_VERSION_COMPLETE from ${vulkan_core_h}")
    endif()

    if(vulkan_version STREQUAL "1.3.275")
        set(vulkan_headers_sha512 "adebfc61501e67367d366a8b17833d064f925ada6480641ef3c128bbda3852087e02d67a09e90b2c188a47494b7e47a87db0d039465858e765e89dc6c2b370d7")
    else()
        message(FATAL_ERROR "No pinned SHA512 for Vulkan-Headers v${vulkan_version}; update android-vulkan-version.cmake before downloading")
    endif()

    set(vulkan_version "${vulkan_version}" PARENT_SCOPE)
    set(vulkan_headers_sha512 "${vulkan_headers_sha512}" PARENT_SCOPE)
endfunction()
