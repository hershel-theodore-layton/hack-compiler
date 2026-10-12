#!/bin/sh

# hack-compiler is MIT licensed, see /LICENSE.
set -eu

port=10641
replace=no
launch_mode=server
resource=

option_error() {
  echo "$1" >&2
  usage >&2
  exit 1
}

usage() {
  echo "Usage: $0 [-p PORT] [-d] -b PATH"
  echo '  -b, -r PATH  Select the resource to run.'
  echo '  -d  Run as a daemon.'
}

while getopts ':hp:b:r:gd' option; do
  case "$option" in
    h) usage; exit 0 ;;
    g) ;;
    p) port=$OPTARG ;;
    d) launch_mode=daemon ;;
    b|r) resource=$OPTARG ;;
    \?) option_error "Unknown option: -$OPTARG" ;;
    :) option_error "Option -$OPTARG requires an argument" ;;
  esac
done
shift "$((OPTIND - 1))"
test "$#" -eq 0 || option_error "Unexpected argument: $1"
case "$port" in
  ''|*[!0-9]*) option_error 'Port must be an integer from 1 to 65535' ;;
esac
if ! { [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; }; then
  option_error 'Port must be an integer from 1 to 65535'
fi
test -n "$resource" || option_error 'Select a resource with -b PATH or -r PATH.'
test -f "$resource" || option_error "Resource file not found: $resource"
resource=$(realpath --relative-to="$PWD" "$resource")

work_root="${TMPDIR:-/tmp}/hack-compiler-serve-resource"
mkdir -p "$work_root"
work_dir=$(mktemp -d "$work_root/server.XXXXXX")
server_pid=
cleanup() {
  if [ -n "$server_pid" ]; then
    kill -INT "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
if hhvm --hphp --help 2>&1 | grep -q -- '--target'; then
  set -- --target hhbc
fi
hhvm --hphp "$@" "$resource" --output-dir "$work_dir"
set --

set -- -dhhvm.jit_retranslate_all_request=5
if [ "$launch_mode" = daemon ]; then
  command -v curl > /dev/null || {
    echo 'Daemon mode requires curl.' >&2
    exit 1
  }
  command -v setsid > /dev/null || {
    echo 'Daemon mode requires setsid.' >&2
    exit 1
  }
  set -- "$@" -dhhvm.log.file=/dev/null
fi
if [ "$replace" = no ]; then
  set -- "$@" "-dhhvm.pid_file=$work_dir/www.pid"
fi
start_server() {
  if [ "$launch_mode" = daemon ]; then
    set -- setsid hhvm "$@"
  else
    set -- hhvm "$@"
  fi
  exec "$@" -m server -p "$port" --no-config \
    -vServer.AllowRunAsRoot=1 \
    -vServer.ExitOnBindFail=true \
    -dhhvm.repo.authoritative=true \
    "-dhhvm.repo.path=$work_dir/hhvm.hhbc" \
    "-dhhvm.server.global_document=$resource" \
    "-dhhvm.server.allowed_files[0]=$resource" \
    '-dhhvm.php_file.extensions[resource]=1'
}
if [ "$launch_mode" = daemon ]; then
  start_server "$@" > /dev/null 2>&1 &
else
  start_server "$@" &
fi
server_pid=$!
while :; do
  if [ "$replace" = yes ]; then
    if handshake && [ "$handshake_instance" = "$nonce" ]; then break; fi
  elif [ -s "$work_dir/www.pid" ]; then
    if [ "$launch_mode" != daemon ] ||
       curl --noproxy '*' --silent --head --max-time 1 \
         "http://127.0.0.1:$port/" > /dev/null; then
      break
    fi
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"
    exit 1
  fi
  sleep 0.1
done
rm -rf "$work_dir"
if [ "$launch_mode" = daemon ]; then
  server_pid=
  exit 0
fi
server_status=0
wait "$server_pid" || server_status=$?
server_pid=
exit "$server_status"
