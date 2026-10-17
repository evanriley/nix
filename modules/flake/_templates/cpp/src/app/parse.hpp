#pragma once

#include <cstdint>
#include <expected>
#include <string_view>

namespace app {

inline constexpr std::uint32_t max_count = 100;

enum class parse_error : std::uint8_t {
    empty,
    not_decimal,
    zero,
    too_large,
};

[[nodiscard]] std::expected<std::uint32_t, parse_error> parse_count(std::string_view text);

[[nodiscard]] std::string_view describe(parse_error error);

} // namespace app
