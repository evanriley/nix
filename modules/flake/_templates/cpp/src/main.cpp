#include "app/parse.hpp"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <print>
#include <span>
#include <string_view>

using app::describe;
using app::max_count;
using app::parse_count;

namespace {

int run(std::span<char *const> arguments) {
    if (arguments.size() > 2) {
        std::println(stderr, "usage: app [count]");
        return 2;
    }
    std::uint32_t count = 1;
    if (arguments.size() == 2) {
        const std::string_view text = arguments.back();
        const auto parsed = parse_count(text);
        if (!parsed) {
            std::println(stderr, "Invalid count '{}': {}; expected a whole number from 1 to {}.",
                         text, describe(parsed.error()), max_count);
            return 2;
        }
        count = *parsed;
    }
    for (std::uint32_t line = 0; line < count; ++line) {
        std::println("Hello from app");
    }
    return 0;
}

} // namespace

int main(int argc, char *argv[]) {
    try {
        return run(std::span<char *const>(argv, static_cast<std::size_t>(argc)));
    } catch (const std::exception &error) {
        std::fputs(error.what(), stderr);
        std::fputs("\n", stderr);
        return 1;
    }
}
