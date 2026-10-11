/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string OBSOLETE_SERVER_HEADER = <<<'SH'
#!/bin/sh
set -eu

port=10641
global=no
setup=no
launch_mode=server
bundled=no
trusted=no
resource=

usage() {
  echo "Usage: $0 [-p PORT] [-g] [-s] [-d] [-t] [-e | -b PATH | -r PATH]"
  echo '  -e  Use the resource embedded in this script.'
  echo '  -b, -r PATH  Use and trust an external resource.'
  echo '  -g  Cache the compiled repository under /var/tmp.'
  echo '  -s  Set up VS Code for Docker Native development.'
  echo '  -d  Run as a daemon.'
  echo '  -t  Trust the discovered external resource.'
}

option_error() {
  echo "$1" >&2
  usage >&2
  exit 1
}

while getopts ':hp:b:r:gsdite' option; do
  case "$option" in
    h) usage; exit 0 ;;
    p) port=$OPTARG ;;
    g) global=yes ;;
    s) setup=yes ;;
    d) launch_mode=daemon ;;
    i) option_error 'Interpreter mode (-i) is no longer supported.' ;;
    t) trusted=yes ;;
    e) bundled=yes; trusted=yes ;;
    b|r) resource=$OPTARG; trusted=yes ;;
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
test -f .hhconfig || option_error 'Run this script from the project root.'
if [ "$bundled" = yes ]; then
  test -z "$resource" || option_error '-e cannot be combined with -b or -r.'
else
  if [ -z "$resource" ]; then
    resource=$(find . -type f -name portable-hack-ast-linters-server-bundled.resource | head -n 1)
  fi
  test -f "$resource" || option_error "Bundle file not found: $resource"
  resource=$(realpath --relative-to="$PWD" "$resource")
fi

if [ "$setup" = yes ] && [ ! -f .vscode/settings.json ]; then
  mkdir -p .vscode
  linter_port=$(grep -A 1 'ports' docker-compose.yml | cut -d ':' -f 1 | grep -E -o '[[:digit:]]{5}')
  container_name=$(sed -n 's/^[[:space:]]*container_name:[[:space:]]*//p' docker-compose.yml)
  cat > .vscode/settings.json <<JSON
{
  "editor.detectIndentation": false,
  "editor.tabSize": 2,
  "editor.rulers": [80],
  "hack.remote.docker.containerName": "$container_name",
  "hack.remote.enabled": true,
  "hack.remote.type": "docker",
  "hack.remote.workspacePath": "/mnt/project",
  "lintServer.uri": "http://localhost:$linter_port?action=lint-input&format=vscode-json"
}
JSON
  cat > .vscode/extensions.json <<'JSON'
{
  "recommendations": [
    "pranayagarwal.vscode-hack",
    "hershel-theodore-layton.dead-simple-lint-server-integration"
  ]
}
JSON
fi

name=$(basename "$0")
source_dir=".var/hack-compiler/$name"
cache_dir="$PWD/.var/portable-hack-ast-linters-server"
if [ "$global" = yes ]; then
  cache_dir=/var/tmp/portable-hack-ast-linters-server
fi
mkdir -p "$cache_dir"
if [ "$bundled" = yes ]; then
  mkdir -p "$source_dir"
  resource="$source_dir/source.resource"
  fingerprint="$(sha1sum "$0" | cut -d ' ' -f 1):$PWD"
else
  fingerprint=$(sha1sum "$resource")
fi
changed=yes
if [ -f "$cache_dir/sha1sum.txt" ] &&
   [ "$(cat "$cache_dir/sha1sum.txt")" = "$fingerprint" ]; then
  if [ -f "$cache_dir/hhvm.hhbc" ]; then
    changed=no
  fi
fi

if [ -f "$cache_dir/www.pid" ]; then
  pid=$(cat "$cache_dir/www.pid")
  identity=$(curl --silent --max-time 5 "http://localhost:$port/?action=identify-yourself" || true)
  if [ "$identity" = 'HTL\PhaLintersServer' ]; then
    if [ "$changed" = no ]; then
      echo 'Previous server is identical, nothing to do.'
      exit 0
    fi
    echo 'Previous server is different, replacing it.'
    kill -INT "$pid"
    attempts=0
    while kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 50 ]; do
      sleep 0.1
      attempts=$((attempts + 1))
    done
  else
    echo 'Previous server left a dangling www.pid.'
  fi
  rm -f "$cache_dir/www.pid"
fi

trap 'if [ "$bundled" = yes ]; then rm -f "$resource"; fi' 0
trap 'exit 1' HUP INT TERM
if [ "$changed" = yes ] && [ "$trusted" = no ]; then
  echo "Found the following resource file: $resource"
  echo "If you trust it, type 'I trust this resource' to build and run it."
  read -r confirmation
  test "$confirmation" = 'I trust this resource' || exit 1
fi
if [ "$changed" = yes ]; then
  if [ "$bundled" = yes ]; then
    tail -n +__SOURCE_LINE__ "$0" > "$resource"
  fi
  if hhvm --hphp --help 2>&1 | grep -q -- '--target'; then
    set -- --target hhbc
  fi
  hhvm --hphp "$@" "$resource" --output-dir "$cache_dir"
  set --
  if [ "$bundled" = yes ]; then rm "$resource"; fi
fi
printf '%s\n' "$fingerprint" > "$cache_dir/sha1sum.txt"

if [ "$launch_mode" = daemon ]; then
  set -- -dhhvm.log.file=/dev/null
fi
hhvm -m "$launch_mode" -p "$port" --no-config \
  -vServer.AllowRunAsRoot=1 \
  -dhhvm.repo.authoritative=true \
  "-dhhvm.repo.path=$cache_dir/hhvm.hhbc" \
  "-dhhvm.server.global_document=$resource" \
  "-dhhvm.server.allowed_files[0]=$resource" \
  -dhhvm.jit_retranslate_all_request=5 \
  '-dhhvm.php_file.extensions[resource]=1' \
  "-dhhvm.pid_file=$cache_dir/www.pid" "$@"
SH;
