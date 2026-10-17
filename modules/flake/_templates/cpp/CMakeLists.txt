cmake_minimum_required(VERSION 3.28)
project(app VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# nixpkgs ships clang-scan-deps unwrapped, so module scanning cannot find the standard headers.
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

option(APP_FUZZ "Build the libFuzzer target" OFF)

include(CTest)

set(project_warnings
    -Wall
    -Wextra
    -Wpedantic
    -Wshadow
    -Wconversion
    -Wold-style-cast
    -Wnon-virtual-dtor
    -Woverloaded-virtual
    -Wimplicit-fallthrough)

add_library(${PROJECT_NAME}_core STATIC src/app/parse.cpp)
target_include_directories(${PROJECT_NAME}_core PUBLIC src)
target_compile_options(${PROJECT_NAME}_core PRIVATE ${project_warnings})

add_executable(${PROJECT_NAME} src/main.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE ${PROJECT_NAME}_core)
target_compile_options(${PROJECT_NAME} PRIVATE ${project_warnings})
install(TARGETS ${PROJECT_NAME})

if(BUILD_TESTING)
    find_package(Catch2 3 REQUIRED)
    include(Catch)
    add_executable(${PROJECT_NAME}_test tests/parse_test.cpp)
    target_link_libraries(${PROJECT_NAME}_test PRIVATE ${PROJECT_NAME}_core Catch2::Catch2WithMain)
    target_compile_options(${PROJECT_NAME}_test PRIVATE ${project_warnings})
    catch_discover_tests(${PROJECT_NAME}_test)
endif()

if(APP_FUZZ)
    target_compile_options(${PROJECT_NAME}_core PRIVATE -fsanitize=fuzzer-no-link)
    add_executable(${PROJECT_NAME}_fuzz fuzz/parse_fuzz.cpp)
    target_link_libraries(${PROJECT_NAME}_fuzz PRIVATE ${PROJECT_NAME}_core)
    target_compile_options(${PROJECT_NAME}_fuzz PRIVATE ${project_warnings} -fsanitize=fuzzer)
    target_link_options(${PROJECT_NAME}_fuzz PRIVATE -fsanitize=fuzzer)
endif()
