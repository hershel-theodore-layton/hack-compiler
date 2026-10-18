#!/bin/sh
# hack-compiler is MIT licensed, see /LICENSE.
set -eu

mkdir -p .var
test_dir=$(mktemp -d "$PWD/.var/server-modes.XXXXXX")
mkdir "$test_dir/tmp"
export TMPDIR="$test_dir/tmp"
work_root="$TMPDIR/hack-compiler"
port=${SERVER_TEST_PORT:-10643}
server_pid=
launcher_pid=
external_launcher="$PWD/bin/hack-compiler-serve-resource.sh"
cleanup() {
  if [ -z "$server_pid" ]; then
    for pid_file in "$work_root"/server.*/www.pid \
      "$TMPDIR"/hack-compiler-serve-resource/server.*/www.pid; do
      if [ -f "$pid_file" ]; then kill -INT "$(cat "$pid_file")" 2>/dev/null || true; fi
    done
  else
    kill -INT "$server_pid" 2>/dev/null || true
  fi
  if [ -n "$launcher_pid" ]; then wait "$launcher_pid" 2>/dev/null || true; fi
  rm -rf "$test_dir"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

for mode in resource server server-obsolete; do
  compression_option=${HACK_COMPILER_TEST_COMPRESSED:-}
  if [ "$mode" = resource ]; then compression_option=; fi
  hhvm "$@" bin/hack-compiler.hack $compression_option --mode "$mode" \
    --root tests/fixtures/server.hack.fixture > "$test_dir/$mode"
done
for mode in server server-obsolete; do
  hhvm "$@" bin/hack-compiler.hack ${HACK_COMPILER_TEST_COMPRESSED:-} --mode "$mode" --enable-self-update --typecheck \
    --root tests/fixtures/server.hack.fixture > "$test_dir/$mode-replace"
done
# Both server modes embed the same rewritten resource.
for mode in server server-obsolete; do
  line=$(awk '/^__HACK_COMPILER_RESOURCE__$/ { print NR + 1; exit }' "$test_dir/$mode")
  if [ -n "${HACK_COMPILER_TEST_COMPRESSED:-}" ]; then
    # Use the launcher's extraction helper without starting a server.
    sed -n '/^hack_compiler_extract() {$/,/^}$/p' "$test_dir/$mode" > "$test_dir/extract.sh"
    sh -c '. "$1"; hack_compiler_extract "$2" "$3"' sh \
      "$test_dir/extract.sh" "$test_dir/$mode" "$test_dir/extracted.resource"
  else
    tail -n +"$line" "$test_dir/$mode" > "$test_dir/extracted.resource"
  fi
  if [ "$mode" = server ]; then
    cp "$test_dir/extracted.resource" "$test_dir/server.resource"
  else
    cmp "$test_dir/server.resource" "$test_dir/extracted.resource"
  fi
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

# Daemon launchers exit before their servers do. Repository cleanup also happens
# before shutdown, so wait for the listener rather than a PID or directory.
stop_server() {
  kill -INT "$server_pid"
  attempts=0
  while [ "$attempts" -lt 100 ]; do
    status=0
    curl --noproxy '*' --silent --max-time 1 "http://127.0.0.1:$port/" \
      > /dev/null || status=$?
    if [ "$status" -eq 7 ]; then
      server_pid=
      return
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  echo "Server did not release port $port after SIGINT." >&2
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
server_pid=$(curl --fail --silent "http://localhost:$port/?action=pid")
test "$(curl --silent "http://localhost:$port/?action=paths")" = "$test_dir|$test_dir/server"
test ! -f "$work_root"/server.*/source.resource
# An ordinary relaunch fails promptly without disturbing the running server.
relaunch_status=0
timeout 30 sh ./server -d -p "$port" > refused.log 2>&1 || relaunch_status=$?
test "$relaunch_status" -ne 0
test "$relaunch_status" -ne 124
wait_for_response compiled
# Replacement is opt-in: a normal server cannot complete the handshake.
if sh ./server-replace -d -p "$port" > refused.log 2>&1; then
  echo 'A listener without the handshake must be left running.' >&2
  exit 1
fi
grep -q 'leaving it running' refused.log
wait_for_response compiled
# Some HHVM versions crash during signal-driven shutdown; cleanup must still run.
stop_server
wait "$launcher_pid" || true
launcher_pid=
test -z "$(find "$work_root" -name hhvm.hhbc -print)"
test ! -d .var

rm -f head-response
sh ./server -d -p "$port" > server.log 2>&1
test "$(cat head-response)" = ready
test "$(curl --fail --silent --max-time 1 "http://localhost:$port/")" = compiled
server_pid=$(curl --fail --silent "http://localhost:$port/?action=pid")
test -z "$(find "$work_root" -name hhvm.hhbc -print)"
test ! -f "$work_root"/server.*/source.resource
stop_server

# Legacy options still support VS Code setup.
rm -rf "$work_root"
script=./server-obsolete
rm -f head-response
sh "$script" -e -d -g -s -p "$port" > server.log 2>&1
test "$(cat head-response)" = ready
test "$(curl --fail --silent --max-time 1 "http://localhost:$port/")" = compiled
server_pid=$(curl --fail --silent "http://localhost:$port/?action=pid")
test "$(curl --silent "http://localhost:$port/?action=paths")" = "$test_dir|$test_dir/server-obsolete"
test -z "$(find "$work_root" -name hhvm.hhbc -print)"
test ! -f "$work_root"/server.*/source.resource
grep -q '"hack.remote.docker.containerName": "compiler-test-container"' .vscode/settings.json
grep -q 'localhost:48568?action=lint-input&format=vscode-json' .vscode/settings.json
stop_server

# The standalone launcher accepts both aliases and cleans up foreground output.
external_root="$TMPDIR/hack-compiler-serve-resource"
cp resource portable-hack-ast-linters-server-bundled.resource
external=./portable-hack-ast-linters-server-bundled.resource
sh "$external_launcher" -r "$test_dir/portable-hack-ast-linters-server-bundled.resource" -p "$port" > server.log 2>&1 &
launcher_pid=$!
wait_for_response compiled
server_pid=$(curl --fail --silent "http://localhost:$port/?action=pid")
stop_server
wait "$launcher_pid" || true
launcher_pid=
test -z "$(find "$external_root" -name hhvm.hhbc -print)"

rm -f head-response
sh "$external_launcher" -b "$external" -g -d -p "$port" > server.log 2>&1
test "$(cat head-response)" = ready
test "$(curl --fail --silent --max-time 1 "http://localhost:$port/")" = compiled
server_pid=$(curl --fail --silent "http://localhost:$port/?action=pid")
test -z "$(find "$external_root" -name hhvm.hhbc -print)"
stop_server
# Both replacement modes replace identical launches and each other, without PID files.
control() {
  reply=$(curl --fail --silent "http://localhost:$port/?__hack_compiler_handshake=test")
  pid_namespace=$(readlink /proc/self/ns/pid)
  case "$reply" in "hack-compiler/1:test:$pid_namespace:"*) ;; *) exit 1 ;; esac
  server_pid=${reply##*:}
  instance=${reply#"hack-compiler/1:test:$pid_namespace:"}
  instance=${instance%:*}
  attempts=0
  while [ -d "$work_root/$instance" ] && [ "$attempts" -lt 50 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
  done
}
for replacement in ./server-replace ./server-obsolete-replace; do
  for repeat in 1 2; do
    previous_pid=$server_pid
    sh "$replacement" -e -d -p "$port" > server.log 2>&1
    test "$(curl --fail --silent --max-time 1 "http://localhost:$port/")" = compiled
    control
    test "$server_pid" != "$previous_pid"
    test ! -d "$work_root/$instance"
    test ! -f "$work_root/$instance/www.pid"
    test ! -f "$work_root/$instance/source.resource"
  done
done
cp ./server-replace invalid-replace
if [ -n "${HACK_COMPILER_TEST_COMPRESSED:-}" ]; then
  printf '\nthis is invalid Hack;\n' | gzip -c >> invalid-replace
else
  printf '\nthis is invalid Hack;\n' >> invalid-replace
fi
if sh ./invalid-replace -d -p "$port" > invalid.log 2>&1; then
  echo 'A failed compilation must leave the previous server running.' >&2
  exit 1
fi
# Extraction succeeded and the invalid source reached HHVM's syntax check.
grep -qi 'unexpected token' invalid.log
previous_pid=$server_pid
wait_for_response compiled
control
test "$server_pid" = "$previous_pid"
stop_server
attempts=0
while [ -d "$work_root/$instance" ] && [ "$attempts" -lt 50 ]; do
  sleep 0.1
  attempts=$((attempts + 1))
done
test ! -d "$work_root/$instance"

# Foreground replacement removes its repository while still serving.
sh ./server-replace -p "$port" > server.log 2>&1 &
launcher_pid=$!
wait_for_response compiled
control
test ! -d "$work_root/$instance"
stop_server
wait "$launcher_pid" || true
launcher_pid=
test ! -d "$work_root/$instance"
# The obsolete launcher still asks before running a discovered resource.
if printf 'no\n' | sh "$script" -d -p "$port" > declined.log 2>&1; then
  echo 'An untrusted discovered resource must not run.' >&2
  exit 1
fi
cmp resource "$external"
echo 'Server embedding, cleanup, replacement handshakes, setup, and external resources passed.'
