#include "app/parse.hpp"

#include <catch2/catch_message.hpp>
#include <catch2/catch_test_macros.hpp>

#include <cstdint>
#include <string>

using app::max_count;
using app::parse_count;
using app::parse_error;

TEST_CASE("parse_count_valid_range_returns_value") {
    for (std::uint32_t count = 1; count <= max_count; ++count) {
        CHECK(parse_count(std::to_string(count)) == count);
    }
}

TEST_CASE("parse_count_bounds_accepts_one_and_max") {
    CHECK(parse_count("1") == 1U);
    CHECK(parse_count("100") == 100U);
    CHECK(parse_count("0100") == 100U);
}

TEST_CASE("parse_count_over_max_returns_too_large") {
    CHECK(parse_count("101").error() == parse_error::too_large);
    CHECK(parse_count(std::string(64, '9')).error() == parse_error::too_large);
}

TEST_CASE("parse_count_empty_returns_empty") {
    CHECK(parse_count("").error() == parse_error::empty);
}

TEST_CASE("parse_count_non_digits_returns_not_decimal") {
    for (const char *text : {"a", "12a", "-1", "+1", " 1", "1 ", "1.5", "0x10"}) {
        CAPTURE(text);
        CHECK(parse_count(text).error() == parse_error::not_decimal);
    }
}

TEST_CASE("parse_count_zero_returns_zero") {
    CHECK(parse_count("0").error() == parse_error::zero);
    CHECK(parse_count("000").error() == parse_error::zero);
}
