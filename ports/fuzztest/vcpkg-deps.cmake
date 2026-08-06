# Injected through CMAKE_PROJECT_INCLUDE, so it runs at the end of project() —
# before CMakeLists.txt reaches cmake/BuildDependencies.cmake.
#
# FetchContent honours the FIRST declaration for a given name, so declaring the
# four dependencies here with FIND_PACKAGE_ARGS makes FuzzTest resolve them
# through find_package() against the vcpkg install tree instead of cloning and
# building its own copies inside the port. Without this the package would carry
# a second Abseil and a second GoogleTest, at a different ABI from the ones its
# consumers already link.

find_package(absl CONFIG REQUIRED)
find_package(re2 CONFIG REQUIRED)
find_package(GTest CONFIG REQUIRED)
find_package(antlr4-runtime CONFIG REQUIRED)

include(FetchContent)
FetchContent_Declare(abseil-cpp FIND_PACKAGE_ARGS NAMES absl)
FetchContent_Declare(re2 FIND_PACKAGE_ARGS NAMES re2)
FetchContent_Declare(googletest FIND_PACKAGE_ARGS NAMES GTest)
FetchContent_Declare(antlr_cpp FIND_PACKAGE_ARGS NAMES antlr4-runtime)
