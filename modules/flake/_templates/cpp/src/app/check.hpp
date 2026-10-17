#pragma once

#include <cstdio>
#include <cstdlib>
#include <print>
#include <source_location>

namespace app {

inline void check(bool condition,
                  const std::source_location location = std::source_location::current()) {
    if (!condition) [[unlikely]] {
        std::println(stderr, "{}:{}: check failed", location.file_name(), location.line());
        std::abort();
    }
}

} // namespace app
