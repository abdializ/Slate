#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
clang++ -std=c++20 -Wall -Wextra -Werror -Wno-missing-field-initializers -I "$ROOT" "$ROOT/core/resource_controller.cc" "$ROOT/tests/core_tests.cc" -o "$SCRATCH/core_tests"
"$SCRATCH/core_tests"
clang++ -std=c++20 -Wall -Wextra -Werror -Wno-missing-field-initializers -I "$ROOT" "$ROOT/core/tab_model.cc" "$ROOT/tests/tab_model_tests.cc" -o "$SCRATCH/tab_tests"
"$SCRATCH/tab_tests"
clang++ -std=c++20 -Wall -Wextra -Werror -Wno-missing-field-initializers -I "$ROOT" "$ROOT/core/tab_model.cc" "$ROOT/core/resource_controller.cc" "$ROOT/tests/protection_tests.cc" -o "$SCRATCH/protection_tests"
"$SCRATCH/protection_tests"
clang++ -std=c++20 -Wall -Wextra -Werror -Wno-missing-field-initializers -I "$ROOT" "$ROOT/core/navigation.cc" "$ROOT/tests/navigation_tests.cc" -o "$SCRATCH/navigation_tests"
"$SCRATCH/navigation_tests"
clang++ -std=c++20 -Wall -Wextra -Werror -Wno-missing-field-initializers -I "$ROOT" -DSLATE_SOURCE_DIR="\"$ROOT\"" \
 "$ROOT/core/shields.cc" "$ROOT/filtering/network_engine.cc" "$ROOT/tests/shields_tests.cc" -o "$SCRATCH/shields_tests"
"$SCRATCH/shields_tests"
