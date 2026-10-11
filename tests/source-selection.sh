#!/bin/sh
# hack-compiler is MIT licensed, see /LICENSE.
set -eu

mkdir -p .var
test_dir=$(mktemp -d "$PWD/.var/source-selection.XXXXXX")
trap 'rm -rf "$test_dir"' 0
trap 'exit 1' HUP INT TERM
compiler="$PWD/bin/hack-compiler.hack"
mkdir -p "$test_dir/sources/nested" "$test_dir/sources/skipped" "$test_dir/other"
printf 'const int A = 1;\n' > "$test_dir/sources/a.hack"
printf 'const int B = 2;\n' > "$test_dir/sources/nested/b.hack"
printf 'const int SKIP = 3;\n' > "$test_dir/sources/skipped/c.hack"
printf 'const int PREFIX = 4;\n' > "$test_dir/sources/prefix-one.hack"
printf 'not Hack\n' > "$test_dir/sources/readme.txt"
printf 'const int Z = 5;\n' > "$test_dir/other/z.hack"

cd "$test_dir"
mkdir -p .var
hhvm "$@" "$compiler" --mode resource \
  --root sources --root sources/a.hack --root "$test_dir/other/z.hack" \
  --exclude ./sources/skipped --exclude sources/prefix \
  > actual.resource
cat > expected.resource <<'RESOURCE'
///// other/z.hack /////
const int Z = 5;

///// sources/a.hack /////
const int A = 1;

///// sources/nested/b.hack /////
const int B = 2;
RESOURCE
cmp actual.resource expected.resource
expect_failure() {
  if hhvm "$@" > invalid.resource 2> invalid.error; then
    echo 'Invalid compiler arguments must fail.' >&2
    exit 1
  fi
  test ! -s invalid.resource
  test -s invalid.error
}
expect_failure "$@" "$compiler" --mode resource --root sources --exclude sources
expect_failure "$@" "$compiler" --root sources
expect_failure "$@" "$compiler" --mode resource --root nonexistent
echo 'Explicit modes, recursive roots, overlapping roots, exclusions, and relative paths passed.'
