add_executable(tickscope_tests
  types_test.cpp
)
target_link_libraries(tickscope_tests PRIVATE tickscope_core GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(tickscope_tests)
