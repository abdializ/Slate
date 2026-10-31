// File purpose: Declares address-bar parsing into a URL, a Google search, or an invalid input.

#pragma once
#include <string>
#include <string_view>
namespace slate {
enum class InputKind { Url, Search, Invalid };
// Slate note: The UI receives both the classification and the final destination URL.
struct NavigationDecision {
 InputKind kind = InputKind::Invalid;
 std::string url;
};
// Address-bar parsing only. Rejects javascript/data/file schemes. Bare words
// become a Google HTTPS search; hostnames become https URLs.
NavigationDecision resolve_address_bar(std::string_view raw);
}
