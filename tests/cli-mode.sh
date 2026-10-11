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
hhvm "$@" bin/hack-compiler.hack --mode cli --root tests/fixtures/cli.hack.fixture \
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

echo 'CLI arguments, environment, stdin, exit status, and cleanup passed.'
