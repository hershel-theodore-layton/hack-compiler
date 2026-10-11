#!/bin/sh

# hack-compiler is MIT licensed, see /LICENSE.
set -eu

port=10641
global=no
launch_mode=server
resource=

option_error() {
  echo "$1" >&2
  usage >&2
  exit 1
}

usage() {
  echo "Usage: $0 [-p PORT] [-g] [-d] -b PATH"
  echo '  -b, -r PATH  Select the resource to run.'
  echo '  -g  Compile the repository under /var/tmp.'
  echo '  -d  Run as a daemon.'
}

while getopts ':hp:b:r:gd' option; do
  case "$option" in
    h) usage; exit 0 ;;
    p) port=$OPTARG ;;
    g) global=yes ;;
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

work_root="$PWD/.var/hack-compiler-serve-resource"
if [ "$global" = yes ]; then
  work_root=/var/tmp/hack-compiler-serve-resource
fi
mkdir -p "$work_root"
work_dir=$(mktemp -d "$work_root/server.XXXXXX")
trap 'rm -rf "$work_dir"' 0
trap 'exit 1' HUP INT TERM
if hhvm --hphp --help 2>&1 | grep -q -- '--target'; then
  set -- --target hhbc
fi
hhvm --hphp "$@" "$resource" --output-dir "$work_dir"
set --

if [ "$launch_mode" = daemon ]; then
  set -- -dhhvm.log.file=/dev/null
fi
hhvm -m "$launch_mode" -p "$port" --no-config \
  -vServer.AllowRunAsRoot=1 \
  -dhhvm.repo.authoritative=true \
  "-dhhvm.repo.path=$work_dir/hhvm.hhbc" \
  "-dhhvm.server.allowed_files[0]=$resource" \
  "-dhhvm.server.global_document=$resource" \
  -dhhvm.jit_retranslate_all_request=5 \
  '-dhhvm.php_file.extensions[resource]=1' \
  "-dhhvm.pid_file=$work_dir/www.pid" "$@"
if [ "$launch_mode" = daemon ]; then trap - 0; fi
