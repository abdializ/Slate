#include "core/navigation.h"
#include <cstdlib>
#include <iostream>
using namespace slate;
void check(bool condition) { if(!condition) std::abort(); }
int main() {
 auto search=resolve_address_bar("mitosis");
 check(search.kind==InputKind::Search && search.url=="https://www.google.com/search?q=mitosis");
 auto words=resolve_address_bar("  office hours  ");
 check(words.kind==InputKind::Search && words.url.find("q=office%20hours")!=std::string::npos);
 auto host=resolve_address_bar("google.com");
 check(host.kind==InputKind::Url && host.url=="https://google.com");
 auto path=resolve_address_bar("example.edu/lab");
 check(path.kind==InputKind::Url && path.url=="https://example.edu/lab");
 auto https=resolve_address_bar("https://classroom.google.com");
 check(https.kind==InputKind::Url && https.url=="https://classroom.google.com");
 auto local=resolve_address_bar("localhost:8766");
 check(local.kind==InputKind::Url && local.url=="http://localhost:8766");
 auto blank=resolve_address_bar("about:blank");
 check(blank.kind==InputKind::Url && blank.url=="about:blank");
 check(resolve_address_bar("javascript:alert(1)").kind==InputKind::Invalid);
 check(resolve_address_bar("data:text/html,hi").kind==InputKind::Invalid);
 check(resolve_address_bar("file:///etc/passwd").kind==InputKind::Invalid);
 check(resolve_address_bar("").kind==InputKind::Invalid);
 std::cout << "Address-bar URL vs Google search parsing passed\n";
}
