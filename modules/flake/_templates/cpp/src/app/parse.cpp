#include "app/parse.hpp"

#include <cstdint>
#include <expected>
#include <string_view>

namespace app {

std::expected<std::uint32_t, parse_error> parse_count(std::string_view text) {
    constexpr std::uint32_t decimal_base = 10;
    if (text.empty()) {
        return std::unexpected(parse_error::empty);
    }
    std::uint32_t value = 0;
    for (const char digit : text) {
        if (digit < '0' || digit > '9') {
            return std::unexpected(parse_error::not_decimal);
        }
        if (value <= max_count) {
            value = (value * decimal_base) + static_cast<std::uint32_t>(digit - '0');
        }
    }
    if (value == 0) {
        return std::unexpected(parse_error::zero);
    }
    if (value > max_count) {
        return std::unexpected(parse_error::too_large);
    }
    return value;
}

std::string_view describe(parse_error error) {
    switch (error) {
    case parse_error::empty:
        return "it is empty";
    case parse_error::not_decimal:
        return "it is not a decimal number";
    case parse_error::zero:
        return "it is zero";
    case parse_error::too_large:
        return "it is too large";
    }
    return "it is invalid";
}

} // namespace app
