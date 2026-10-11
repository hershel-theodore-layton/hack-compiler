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
printf 'namespace TypecheckFixture;\nfunction path()[defaults]: string { return __FILE__.__DIR__; }\n' > "$test_dir/paths.hack"
hhvm "$@" bin/hack-compiler.hack --typecheck --mode server \
  --root "$test_dir/paths.hack" > "$test_dir/paths.sh"
grep -Fq "getenv('HACK_COMPILER_SERVER_FILE')" "$test_dir/paths.sh"
# Constant contexts must fail visibly rather than retain a temporary path.
printf 'namespace TypecheckFixture;\nconst string FILE = __FILE__;\n<<__EntryPoint>> function main(): void { echo FILE; }\n' > "$test_dir/constant.hack"
if hhvm "$@" bin/hack-compiler.hack --typecheck --mode server \
  --root "$test_dir/constant.hack" > "$test_dir/failed" 2> "$test_dir/error"; then
  echo 'A rewritten constant initializer must fail typechecking.' >&2
  exit 1
fi
test ! -s "$test_dir/failed"
grep -q 'Resource typecheck failed' "$test_dir/error"
hhvm "$@" bin/hack-compiler.hack --mode server \
  --root "$test_dir/constant.hack" > "$test_dir/constant.sh"
line=$(awk '/^__HACK_COMPILER_RESOURCE__$/ { print NR + 1; exit }' "$test_dir/constant.sh")
tail -n +"$line" "$test_dir/constant.sh" > "$test_dir/constant.resource"
if hhvm "$@" "$test_dir/constant.resource" > "$test_dir/failed" 2> "$test_dir/error"; then
  echo 'Without --typecheck, the rewritten constant must fail at runtime.' >&2
  exit 1
fi
grep -q 'Expected constant expression' "$test_dir/error"
# The transformed source, rather than the original pure expression, must be checked.
printf 'namespace TypecheckFixture;\nfunction path()[]: string { return __FILE__; }\n' > "$test_dir/pure-path.hack"
if hhvm "$@" bin/hack-compiler.hack --typecheck --mode server \
  --root "$test_dir/pure-path.hack" > "$test_dir/failed" 2> "$test_dir/error"; then
  echo 'An illegal effect introduced by path rewriting must fail.' >&2
  exit 1
fi
test ! -s "$test_dir/failed"
grep -q 'Resource typecheck failed' "$test_dir/error"
echo 'Resource typechecking and diagnostics passed.'
