/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string SERVER_OPTIONS = <<<'SH'
#!/bin/sh
set -eu

port=10641
launch_mode=server
bundled=yes
replace=no
legacy=no
trusted=yes
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
SH;
