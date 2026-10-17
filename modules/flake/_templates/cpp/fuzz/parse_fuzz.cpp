#include "app/check.hpp"
#include "app/parse.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data, std::size_t size) {
    const std::span bytes(data, size);
    const std::string text(bytes.begin(), bytes.end());
    const auto parsed = app::parse_count(text);
    if (parsed) {
        app::check(*parsed >= 1 && *parsed <= app::max_count);
    }
    return 0;
}
