#pragma once
#include <string>
#include <string_view>
namespace slate {
enum class InputKind { Url, Search, Invalid };
struct NavigationDecision {
 InputKind kind = InputKind::Invalid;
 std::string url;
};
// Address-bar parsing only. Rejects javascript/data/file schemes. Bare words
// become a Google HTTPS search; hostnames become https URLs.
NavigationDecision resolve_address_bar(std::string_view raw);
}
