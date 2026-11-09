#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <stdexcept>
#include <charconv>

struct ByteRange { int64_t first, last; bool partial; };
inline int64_t decimal(const std::string& text) {
    int64_t value = 0;
    auto result = std::from_chars(text.data(), text.data() + text.size(), value);
    if (text.empty() || result.ec != std::errc() || result.ptr != text.data() + text.size() || value < 0)
        throw std::invalid_argument("Invalid byte range");
    return value;
}
inline ByteRange parse_range(const std::optional<std::string>& header, int64_t size) {
    if (size <= 0) throw std::invalid_argument("Empty file");
    if (!header) return {0, size - 1, false};
    const auto& h = *header;
    if (h.rfind("bytes=", 0) || h.find(',') != std::string::npos) throw std::invalid_argument("Unsupported range");
    auto dash = h.find('-', 6);
    if (dash == std::string::npos) throw std::invalid_argument("Invalid range");
    auto a = h.substr(6, dash - 6), b = h.substr(dash + 1);
    if (a.empty()) {
        auto suffix = decimal(b);
        if (suffix == 0) throw std::invalid_argument("Empty suffix");
        return {size - std::min(size, suffix), size - 1, true};
    }
    auto first = decimal(a), last = b.empty() ? size - 1 : std::min(decimal(b), size - 1);
    if (first >= size || last < first) throw std::invalid_argument("Unsatisfiable range");
    return {first, last, true};
}
