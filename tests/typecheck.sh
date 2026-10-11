#!/bin/sh
# hack-compiler is MIT licensed, see /LICENSE.
set -eu

mkdir -p .var
test_dir=$(mktemp -d "$PWD/.var/typecheck.XXXXXX")
trap 'rm -rf "$test_dir"' 0
trap 'exit 1' HUP INT TERM
mkdir "$test_dir/tmp"
export TMPDIR="$test_dir/tmp"
printf "namespace TypecheckFixture;\nfunction answer()[]: int { return 42; }\n" > "$test_dir/valid.hack"
printf "namespace TypecheckFixture;\nfunction answer()[]: int { return 'wrong'; }\n" > "$test_dir/invalid.hack"

hhvm "$@" bin/hack-compiler.hack --mode resource --root "$test_dir/valid.hack" \
  > "$test_dir/expected"
hhvm "$@" bin/hack-compiler.hack --typecheck --mode resource \
  --root "$test_dir/valid.hack" > "$test_dir/actual"
cmp "$test_dir/expected" "$test_dir/actual"
if hhvm "$@" bin/hack-compiler.hack --mode resource \
  --root "$test_dir/invalid.hack" --typecheck > "$test_dir/failed" 2> "$test_dir/error"; then
  echo 'A resource with a type error must fail.' >&2
  exit 1
fi
test ! -s "$test_dir/failed"
grep -q 'Resource typecheck failed' "$test_dir/error"
grep -q 'Invalid return type' "$test_dir/error"
test -z "$(find "$test_dir/tmp" -maxdepth 1 -name 'hack-compiler.*' -print)"
echo 'Resource typechecking and diagnostics passed.'
