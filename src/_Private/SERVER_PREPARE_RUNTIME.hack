/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string SERVER_PREPARE_RUNTIME = <<<'SH'
if [ "$launch_mode" = daemon ]; then
  command -v setsid > /dev/null || {
    echo 'Daemon mode requires setsid.' >&2
    exit 1
  }
fi
work_root="${TMPDIR:-/tmp}/hack-compiler"
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

if [ "$trusted" = no ]; then
  echo "Found the following resource file: $resource"
  echo "If you trust it, type 'I trust this resource' to build and run it."
  read -r confirmation
  test "$confirmation" = 'I trust this resource' || exit 1
fi
if [ "$bundled" = yes ]; then
  resource=source.resource
  tail -n +__SOURCE_LINE__ "$0" > "$work_dir/$resource"
fi
if [ "$replace" = yes ]; then hhvm --lint "$work_dir/$resource" > /dev/null; fi
if hhvm --hphp --help 2>&1 | grep -q -- '--target'; then
  set -- --target hhbc
fi
if [ "$bundled" = yes ]; then set -- "$@" --input-dir "$work_dir"; fi
hhvm --hphp "$@" "$resource" --output-dir "$work_dir"
set --
if [ "$legacy" = yes ]; then set -- -dhhvm.jit_retranslate_all_request=5; fi
if [ "$bundled" = yes ]; then rm "$work_dir/$resource"; fi
export HACK_COMPILER_SERVER_FILE=$(realpath "$0")
SH;
