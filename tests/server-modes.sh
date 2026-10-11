#!/bin/sh
# hack-compiler is MIT licensed, see /LICENSE.
set -eu

mkdir -p .var
test_dir=$(mktemp -d "$PWD/.var/server-modes.XXXXXX")
port=${SERVER_TEST_PORT:-10643}
server_pid=
launcher_pid=
global_cache=/var/tmp/portable-hack-ast-linters-server
external_launcher="$PWD/bin/hack-compiler-serve-resource.sh"
cleanup() {
  if [ -z "$server_pid" ]; then
    for pid_file in "$test_dir"/.var/hack-compiler/server.*/www.pid \
      "$test_dir"/.var/hack-compiler-serve-resource/server.*/www.pid; do
      if [ -f "$pid_file" ]; then kill -INT "$(cat "$pid_file")" 2>/dev/null || true; fi
    done
  else
    kill -INT "$server_pid" 2>/dev/null || true
  fi
  if [ -n "$launcher_pid" ]; then wait "$launcher_pid" 2>/dev/null || true; fi
  rm -rf "$test_dir" "$global_cache"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

for mode in resource server server-obsolete; do
  hhvm "$@" bin/hack-compiler.hack --mode "$mode" \
    --root tests/fixtures/server.hack.fixture > "$test_dir/$mode"
done
for mode in server server-obsolete; do
  line=$(awk '/^__HACK_COMPILER_RESOURCE__$/ { print NR + 1; exit }' "$test_dir/$mode")
  tail -n +"$line" "$test_dir/$mode" > "$test_dir/extracted.resource"
  cmp "$test_dir/resource" "$test_dir/extracted.resource"
  sh "$test_dir/$mode" -h > /dev/null
done

for launcher in "$test_dir/server" "$test_dir/server-obsolete" "$external_launcher"; do
  if sh "$launcher" -i > "$test_dir/invalid.log" 2>&1; then
    echo 'Interpreter mode must be rejected.' >&2
    exit 1
  fi
  if [ "$launcher" = "$test_dir/server-obsolete" ]; then
    grep -q 'no longer supported' "$test_dir/invalid.log"
  fi
done

wait_for_response() {
  expected=$1
  attempts=0
  while [ "$attempts" -lt 100 ]; do
    response=$(curl --silent --max-time 1 "http://localhost:$port/" || true)
    if [ "$response" = "$expected" ]; then return; fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  tail -n 15 "$test_dir/server.log" >&2
  echo "Expected HTTP response: $expected; got: $response" >&2
  exit 1
}

cp .hhconfig "$test_dir/.hhconfig"
cat > "$test_dir/docker-compose.yml" <<YAML
services:
  hhvm:
    container_name: compiler-test-container
    ports:
      - 48568:$port
YAML

cd "$test_dir"
sh ./server -e -p "$port" > server.log 2>&1 &
launcher_pid=$!
wait_for_response compiled
server_pid=$(cat .var/hack-compiler/server.*/www.pid)
test ! -f .var/hack-compiler/server.*/source.resource
# Some HHVM versions crash during signal-driven shutdown; cleanup must still run.
kill -INT "$server_pid"
wait "$launcher_pid" || true
server_pid=
launcher_pid=
test -z "$(find .var/hack-compiler -name hhvm.hhbc -print)"

sh ./server -d -p "$port" > server.log 2>&1
wait_for_response compiled
server_pid=$(cat .var/hack-compiler/server.*/www.pid)
test -f .var/hack-compiler/server.*/hhvm.hhbc
test ! -f .var/hack-compiler/server.*/source.resource
kill -INT "$server_pid"
server_pid=

# Run this test in an isolated container: the legacy global cache has a fixed path.
script=./server-obsolete
sh "$script" -e -d -g -s -p "$port" > server.log 2>&1
wait_for_response compiled
server_pid=$(cat "$global_cache/www.pid")
test -f "$global_cache/hhvm.hhbc"
test ! -f ".var/hack-compiler/$(basename "$script")/source.resource"
grep -q '"hack.remote.docker.containerName": "compiler-test-container"' .vscode/settings.json
grep -q 'localhost:48568?action=lint-input&format=vscode-json' .vscode/settings.json
sh "$script" -e -d -g -s -p "$port" > unchanged.log 2>&1
grep -q 'Previous server is identical' unchanged.log
test "$(cat "$global_cache/www.pid")" = "$server_pid"

# Changing only the embedded source must rebuild and replace the running server.
sed "s/'compiled'/'recompiled'/" "$script" > rebuilt.sh
mv rebuilt.sh "$script"
sh "$script" -e -d -g -p "$port" > server.log 2>&1
wait_for_response recompiled
server_pid=$(cat "$global_cache/www.pid")
test ! -f ".var/hack-compiler/$(basename "$script")/source.resource"
kill -INT "$server_pid"
server_pid=

# The standalone launcher accepts both aliases and cleans up foreground output.
external_root=.var/hack-compiler-serve-resource
cp resource portable-hack-ast-linters-server-bundled.resource
external=./portable-hack-ast-linters-server-bundled.resource
sh "$external_launcher" -r "$test_dir/portable-hack-ast-linters-server-bundled.resource" -p "$port" > server.log 2>&1 &
launcher_pid=$!
wait_for_response compiled
server_pid=$(cat "$external_root"/server.*/www.pid)
kill -INT "$server_pid"
wait "$launcher_pid" || true
server_pid=
launcher_pid=
test -z "$(find "$external_root" -name hhvm.hhbc -print)"

sh "$external_launcher" -b "$external" -d -p "$port" > server.log 2>&1
wait_for_response compiled
server_pid=$(cat "$external_root"/server.*/www.pid)
test -f "$external_root"/server.*/hhvm.hhbc
kill -INT "$server_pid"
server_pid=
# The obsolete launcher still asks before running a discovered resource.
if printf 'no\n' | sh "$script" -d -p "$port" > declined.log 2>&1; then
  echo 'An untrusted discovered resource must not run.' >&2
  exit 1
fi
cmp resource "$external"
echo 'Server embedding, cleanup, caching, replacement, setup, and external resources passed.'
