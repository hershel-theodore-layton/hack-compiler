/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string SERVER_HEADER = <<<'SH'
#!/bin/sh
set -eu

port=10641
launch_mode=server
while getopts ':hdep:' option; do
  case "$option" in
    h) echo "Usage: $0 [-d] [-e] [-p PORT]"; exit 0 ;;
    d) launch_mode=daemon ;;
    e) ;;
    p) port=$OPTARG ;;
    *) echo "Usage: $0 [-d] [-e] [-p PORT]" >&2; exit 1 ;;
  esac
done
shift "$((OPTIND - 1))"
test "$#" -eq 0 || { echo "Unexpected argument: $1" >&2; exit 1; }

mkdir -p .var/hack-compiler
work_dir=$(mktemp -d "$PWD/.var/hack-compiler/server.XXXXXX")
resource=".var/hack-compiler/$(basename "$work_dir")/source.resource"
trap 'rm -rf "$work_dir"' 0
trap 'exit 1' HUP INT TERM
tail -n +__SOURCE_LINE__ "$0" > "$resource"
if hhvm --hphp --help 2>&1 | grep -q -- '--target'; then
  set -- --target hhbc
fi
hhvm --hphp "$@" "$resource" --output-dir "$work_dir"
set --
rm "$resource"
if [ "$launch_mode" = daemon ]; then
  set -- -dhhvm.log.file=/dev/null
fi
export HACK_COMPILER_SERVER_FILE=$(realpath "$0")
hhvm -m "$launch_mode" -p "$port" --no-config \
  -vServer.AllowRunAsRoot=1 \
  -dhhvm.repo.authoritative=true \
  "-dhhvm.repo.path=$work_dir/hhvm.hhbc" \
  "-dhhvm.pid_file=$work_dir/www.pid" \
  "-dhhvm.server.global_document=$resource" \
  "-dhhvm.server.allowed_files[0]=$resource" \
  '-dhhvm.php_file.extensions[resource]=1' "$@"
if [ "$launch_mode" = daemon ]; then trap - 0; fi
SH;
