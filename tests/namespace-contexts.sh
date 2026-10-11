#!/bin/sh
# hack-compiler is MIT licensed, see /LICENSE.
set -eu

mkdir -p .var
# These inputs intentionally reuse import aliases across namespace declarations.
# The .fixture suffix keeps project lint rules from rejecting the test cases.
hhvm "$@" bin/hack-compiler.hack --mode resource \
  --root tests/fixtures/namespaces-a.hack.fixture \
  --root tests/fixtures/namespaces-b.hack.fixture \
  > .var/namespace-contexts.hack

test "$(hhvm .var/namespace-contexts.hack)" = '3|7|2|4'
echo 'Namespace changes and import resets within and between files passed.'
