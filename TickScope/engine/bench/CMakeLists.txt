add_executable(tickscope_bench
  order_book_bench.cpp
)
target_link_libraries(tickscope_bench PRIVATE tickscope_core benchmark::benchmark_main)
