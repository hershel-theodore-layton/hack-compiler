#!/bin/sh
# hack-compiler is MIT licensed, see /LICENSE.
set -eu

mkdir -p .var
test_dir=$(mktemp -d "$PWD/.var/cli-mode.XXXXXX")
trap 'rm -rf "$test_dir"' 0
trap 'exit 1' HUP INT TERM
mkdir "$test_dir/tmp"
export TMPDIR="$test_dir/tmp"
export HACK_COMPILER_CLI_TEST='spaces, $variables, and "quotes"'
export HACK_COMPILER_CLI_TEST_EXIT=0
for compression in plain compressed; do
  compression_option=
  if [ "$compression" = compressed ]; then compression_option=--compressed; fi
  # The empty option intentionally expands to no arguments.
  hhvm "$@" bin/hack-compiler.hack $compression_option --mode cli --root tests/fixtures/cli.hack.fixture \
    > "$test_dir/cli.sh"
  # Runtime options go before the resource; arguments on either side retain their order.
  quoted="a'b\"c"
  multiline='first line
second line
'
  printf 'standard input\n' | hhvm "$@" -d memory_limit=128M tests/fixtures/cli.hack.fixture \
    before '' 'two words' '$HOME; echo hello' after "$quoted" "$multiline" '--hhvm-args' '--' > "$test_dir/expected"
  printf 'standard input\n' | sh "$test_dir/cli.sh" before '' \
    --hhvm-args -d memory_limit=128M -- \
    'two words' '$HOME; echo hello' after "$quoted" "$multiline" '--hhvm-args' '--' > "$test_dir/actual"
  cmp "$test_dir/expected" "$test_dir/actual"
  # Without a delimiter, all arguments following the marker belong to HHVM.
  hhvm "$@" -d memory_limit=128M tests/fixtures/cli.hack.fixture < /dev/null > "$test_dir/expected"
  sh "$test_dir/cli.sh" --hhvm-args -d memory_limit=128M < /dev/null > "$test_dir/actual"
  cmp "$test_dir/expected" "$test_dir/actual"
  status=0
  HACK_COMPILER_CLI_TEST_EXIT=17 sh "$test_dir/cli.sh" < /dev/null \
    > "$test_dir/failed" || status=$?
  test "$status" -eq 17
  test -z "$(find "$test_dir/tmp" -maxdepth 1 -name 'hack-compiler-cli.*' -print)"

  echo "CLI $compression: arguments, environment, stdin, exit status, and cleanup passed."
done

if hhvm "$@" bin/hack-compiler.hack --mode resource --compressed \
  --root tests/fixtures/cli.hack.fixture > "$test_dir/invalid" 2> "$test_dir/error"; then
  echo 'Compression must require a shell launcher.' >&2
  exit 1
fi
grep -q -- '--compressed requires a shell launcher' "$test_dir/error"
test ! -s "$test_dir/invalid"

# The final loop iteration leaves the compressed launcher in cli.sh.
# A corrupt payload must fail before invoking the application and still clean up.
sed '/^__HACK_COMPILER_RESOURCE__$/q' "$test_dir/cli.sh" > "$test_dir/corrupt.sh"
printf 'invalid gzip payload' >> "$test_dir/corrupt.sh"
if sh "$test_dir/corrupt.sh" < /dev/null > "$test_dir/actual" 2> "$test_dir/error"; then
  echo 'Corrupt compressed source must fail.' >&2
  exit 1
fi
test ! -s "$test_dir/actual"
grep -q gzip "$test_dir/error"
test -z "$(find "$test_dir/tmp" -maxdepth 1 -name 'hack-compiler-cli.*' -print)"
echo 'Compression validation and failed extraction cleanup passed.'
