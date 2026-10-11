#!/bin/sh
set -eu

hack_compiler_cli_directory=$(mktemp -d "${TMPDIR:-/tmp}/hack-compiler-cli.XXXXXX")
trap 'rm -rf "$hack_compiler_cli_directory"' 0
trap 'exit 1' HUP INT TERM
tail -n +39 "$0" > "$hack_compiler_cli_directory/source.resource"

# Quote each argument before rebuilding the two argument lists in POSIX sh.
hack_compiler_cli_quote() {
  hack_compiler_cli_value=$1
  printf "'"
  while case "$hack_compiler_cli_value" in *\'*) true ;; *) false ;; esac; do
    printf '%s' "${hack_compiler_cli_value%%\'*}" "'\\''"
    hack_compiler_cli_value=${hack_compiler_cli_value#*\'}
  done
  printf "%s' " "$hack_compiler_cli_value"
}

hack_compiler_cli_mode=script
hack_compiler_cli_hhvm_arguments=
hack_compiler_cli_script_arguments=
for hack_compiler_cli_argument in "$@"; do
  case "$hack_compiler_cli_mode:$hack_compiler_cli_argument" in
    script:--hhvm-args) hack_compiler_cli_mode=hhvm ;;
    hhvm:--) hack_compiler_cli_mode=remaining ;;
    hhvm:*)
      hack_compiler_cli_hhvm_arguments="$hack_compiler_cli_hhvm_arguments$(hack_compiler_cli_quote "$hack_compiler_cli_argument")"
      ;;
    *)
      hack_compiler_cli_script_arguments="$hack_compiler_cli_script_arguments$(hack_compiler_cli_quote "$hack_compiler_cli_argument")"
      ;;
  esac
done
eval "set -- $hack_compiler_cli_hhvm_arguments \"\$hack_compiler_cli_directory/source.resource\" $hack_compiler_cli_script_arguments"
hhvm "$@"
exit 0
__HACK_COMPILER_RESOURCE__
///// bin/hack-compiler.hack /////
namespace HTL\HackCompiler\CLI;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH;
use namespace HH\Lib\Str;
use namespace HTL\HackCompiler;
use type InvalidArgumentException;
use function array_reduce, dirname;
use const PHP_EOL;

/**
 * @license MIT-0
 * @copyright Hershel Theodore Layton, 2025
 *
 * This function is licensed under MIT-0. It may be copied freely without
 * restriction. Not even this docblock need to be preserved.
 */
function initialize_autoloader()[defaults]: void {
  if (!Str\ends_with(__FILE__, '.hack') || HH\autoload_is_native()) {
    return;
  }

  $invoke_autoloader = () ==> {
    try {
      // Abuse the poor typing of array_reduce to invoke a dynamic callable without hh_client noticing
      array_reduce(
        vec[null],
        HH\dynamic_fun('Facebook\AutoloadMap\initialize'),
      );
    } catch (InvalidArgumentException $e) {
      echo $e->getMessage();
      exit(1);
    }
  };

  $file = '/vendor/autoload.hack';

  $dir = __DIR__;
  $last_dir = $dir;
  // Dependencies are not available until we have found the autoloader.
  $to_mixed = (mixed $value)[]: mixed ==> $value;

  do {
    if (HH\could_include($dir.$file)) {
      require_once $dir.$file;
      $invoke_autoloader();
      return;
    }

    $last_dir = $dir;
    $dir = dirname($dir) |> $to_mixed($$) as string;
  } while ($last_dir !== $dir);

  echo
    'Could not find vendor/autoload.hack and native autoloading was not enabled. '.
    'You can resolve this by enabling `hhvm.autoload.enabled = true` in your '.
    'INI settings and setting a `hhvm.autoload.db.path`. If you cannot use '.
    'native autoloading, invoke vendor/bin/hh-autoload and try again.'.
    PHP_EOL;
  exit(1);
}

<<__EntryPoint>>
async function main_async()[defaults]: Awaitable<void> {
  initialize_autoloader();
  await HackCompiler\_Private\cli_async();
}

///// src/CompileMode.hack /////
namespace HTL\HackCompiler;
/** hack-compiler is MIT licensed, see /LICENSE. */

enum CompileMode: string {
  CLI = 'cli';
  RESOURCE = 'resource';
  SERVER = 'server';
  SERVER_OBSOLETE = 'server-obsolete';
}

///// src/_Private/ast.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH;
use namespace HH\Lib\{C, Dict, Str, Vec};

function ast_declarations(
  AnyArray<arraykey, mixed> $script,
)[]: AnyArray<arraykey, AnyArray<arraykey, mixed>> {
  $declarations = sub_array($script, 'script_declarations');
  return sub_arrays($declarations, 'elements');
}

function ast_digest_arguments_token(
  AnyArray<arraykey, mixed> $arguments,
)[]: ?AnyArray<arraykey, mixed> {
  $items = ast_list_items($arguments);
  if (
    C\count($items) !== 2 ||
    sub_string($items[0], 'kind') !== 'literal' ||
    sub_string($items[1], 'kind') !== 'literal'
  ) {
    return null;
  }
  $name = Str\trim(ast_node_text($items[0]), "\"'");
  $digest = Str\trim(ast_node_text($items[1]), "\"'");
  if (
    ($name !== 'PhaLinters' && $name !== 'HTL\\PhaLinters') ||
    !Str\starts_with($digest, 'digest:')
  ) {
    return null;
  }
  return sub_array($items[1], 'literal_expression', 'token');
}

/** Locate the first PhaLinters digest directive using the Pragma syntax. */
function ast_digest_token(
  AnyArray<arraykey, mixed> $script,
  bool $attributes,
  bool $directives,
)[]: ?AnyArray<arraykey, mixed> {
  if ($attributes) {
    foreach (ast_nodes_of_kind($script, 'constructor_call') as $call) {
      if (
        ast_node_text(sub_array($call, 'constructor_call_type')) !== 'Pragmas'
      ) {
        continue;
      }
      foreach (
        ast_list_items(sub_array($call, 'constructor_call_argument_list')) as
          $argument
      ) {
        if (sub_string($argument, 'kind') !== 'vector_intrinsic_expression') {
          continue;
        }
        $token = ast_digest_arguments_token(
          sub_array($argument, 'vector_intrinsic_members'),
        );
        if ($token is nonnull) {
          return $token;
        }
      }
    }
  }
  if ($directives) {
    foreach (ast_nodes_of_kind($script, 'function_call_expression') as $call) {
      if (
        ast_node_text(sub_array($call, 'function_call_receiver')) !== 'pragma'
      ) {
        continue;
      }
      $token = ast_digest_arguments_token(
        sub_array($call, 'function_call_argument_list'),
      );
      if ($token is nonnull) {
        return $token;
      }
    }
  }
  return null;
}

function ast_is_file_scoped_namespace(
  AnyArray<arraykey, mixed> $namespace,
)[]: bool {
  return
    sub_string($namespace, 'namespace_body', 'kind') === 'namespace_empty_body';
}

function ast_is_namespace(AnyArray<arraykey, mixed> $node)[]: bool {
  return sub_string($node, 'kind') === 'namespace_declaration';
}

function ast_list_items(
  AnyArray<arraykey, mixed> $node,
)[]: vec<AnyArray<arraykey, mixed>> {
  if (sub_string($node, 'kind') === 'missing') {
    return vec[];
  }
  return Vec\map(
    sub_arrays($node, 'elements'),
    $item ==> sub_array($item, 'list_item'),
  );
}

function ast_namespace_keyword_token(
  AnyArray<arraykey, mixed> $namespace,
)[]: AnyArray<arraykey, mixed> {
  $header = sub_array($namespace, 'namespace_header');
  return sub_array($header, 'namespace_keyword', 'token');
}

function ast_namespace_name_tokens(
  AnyArray<arraykey, mixed> $namespace,
)[]: vec<AnyArray<arraykey, mixed>> {
  $header = sub_array($namespace, 'namespace_header');
  return ast_tokens(sub_array($header, 'namespace_name'));
}

function ast_namespace_semicolon_token(
  AnyArray<arraykey, mixed> $namespace,
)[]: AnyArray<arraykey, mixed> {
  return
    sub_array($namespace, 'namespace_body', 'namespace_semicolon', 'token');
}

function ast_node_text(AnyArray<arraykey, mixed> $node)[]: string {
  return Str\join(Vec\map(ast_tokens($node), ast_token_text<>), '');
}

/** Descendants in source order, including the node itself. */
function ast_nodes_of_kind(
  AnyArray<arraykey, mixed> $node,
  string $kind,
)[]: vec<AnyArray<arraykey, mixed>> {
  $node_kind = sub_string($node, 'kind');
  if ($node_kind === 'token' || $node_kind === 'missing') {
    return vec[];
  }
  $children = $node_kind === 'list'
    ? sub_array($node, 'elements')
    : Dict\filter_keys($node, $key ==> $key !== 'kind');
  $descendants = Vec\map(
    $children,
    $child ==> ast_nodes_of_kind($child as AnyArray<_, _>, $kind),
  )
    |> Vec\flatten($$);
  return
    $node_kind === $kind ? Vec\concat(vec[$node], $descendants) : $descendants;
}

function ast_parse_script(string $source)[]: AnyArray<arraykey, mixed> {
  $parsed = HH\ffp_parse_string($source) as AnyArray<_, _>;
  return sub_array($parsed, 'parse_tree');
}

function ast_token_end(AnyArray<arraykey, mixed> $token)[]: int {
  return ast_token_text_end($token) + sub_int($token, 'trailing_width');
}

function ast_token_text(AnyArray<arraykey, mixed> $token)[]: string {
  return sub_string($token, 'text');
}

function ast_token_text_end(AnyArray<arraykey, mixed> $token)[]: int {
  return ast_token_text_start($token) + sub_int($token, 'width');
}

function ast_token_text_start(AnyArray<arraykey, mixed> $token)[]: int {
  return sub_int($token, 'offset') + sub_int($token, 'leading_width');
}

/** Token payloads in source order, excluding trivia. */
function ast_tokens(
  AnyArray<arraykey, mixed> $node,
)[]: vec<AnyArray<arraykey, mixed>> {
  switch (sub_string($node, 'kind')) {
    case 'token':
      return vec[sub_array($node, 'token')];
    case 'missing':
      return vec[];
    case 'list':
      $children = sub_array($node, 'elements');
      break;
    default:
      $children = Dict\filter_keys($node, $key ==> $key !== 'kind');
  }
  return Vec\map($children, $child ==> ast_tokens($child as AnyArray<_, _>))
    |> Vec\flatten($$);
}

function sub_array(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: AnyArray<arraykey, mixed> {
  return sub_value($array, ...$keys) as AnyArray<_, _>;
}

function sub_arrays(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: AnyArray<arraykey, AnyArray<arraykey, mixed>> {
  return
    Dict\map(sub_array($array, ...$keys), $value ==> $value as AnyArray<_, _>);
}

function sub_int(AnyArray<arraykey, mixed> $array, arraykey ...$keys)[]: int {
  return sub_value($array, ...$keys) as int;
}

function sub_string(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: string {
  return sub_value($array, ...$keys) as string;
}

function sub_value(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: mixed {
  $value = $array;
  foreach ($keys as $key) {
    $value = ($value as AnyArray<_, _>)[$key];
  }
  return $value;
}

///// src/_Private/cli.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH;
use namespace HH\Lib\{C, IO, Str, Vec};
use namespace HTL\HackCompiler;
use type Exception;
use function getcwd, realpath;

async function cli_async()[defaults]: Awaitable<void> {
  $args = Vec\map(HH\global_get('argv') as vec<_>, $arg ==> $arg as string)
    |> Vec\drop($$, 1);
  $output = IO\request_output();
  if (C\is_empty($args) || $args[0] === '--help') {
    await $output->writeAllAsync(
      "Usage: hack-compiler.sh --mode MODE --root PATH [--root PATH...] [--exclude PREFIX...] [--typecheck]\n".
      "Modes: resource, cli, server, server-obsolete.\n".
      "Roots select files or directories of .hack files recursively.\n".
      "Paths are sorted relative to the current directory.\n".
      "--typecheck checks the compiled resource before emitting output.\n".
      "The output is written to stdout.\n",
    );
    exit(C\is_empty($args) ? 1 : 0);
  }
  try {
    $cwd = getcwd() as string;
    $roots = vec[];
    $excludes = vec[];
    $mode = null;
    $typecheck = false;
    while (!C\is_empty($args)) {
      if ($args[0] === '--typecheck') {
        $typecheck = true;
        $args = Vec\drop($args, 1);
        continue;
      }
      invariant(C\count($args) >= 2, '%s requires a value.', $args[0]);
      switch ($args[0]) {
        case '--root':
          $path = realpath($args[1]);
          invariant($path is string, 'Invalid source root: %s', $args[1]);
          $roots[] = $path;
          break;
        case '--mode':
          invariant($mode is null, '--mode may only be passed once.');
          $mode = HackCompiler\CompileMode::assert($args[1]);
          break;
        case '--exclude':
          $path = realpath($args[1]);
          $excludes[] = $path is string
            ? $path
            : (
                Str\starts_with($args[1], '/')
                  ? $args[1]
                  : $cwd.'/'.Str\strip_prefix($args[1], './')
              );
          break;
        default:
          invariant_violation('Unknown option: %s', $args[0]);
      }
      $args = Vec\drop($args, 2);
    }
    invariant($mode is nonnull, '--mode is required.');
    $compiled = await HackCompiler\compile_roots_async(
      $roots,
      $excludes,
      $mode,
      $typecheck,
    );
    await $output->writeAllAsync($compiled);
  } catch (Exception $e) {
    $error = IO\request_error() as nonnull;
    await $error->writeAllAsync($e->getMessage()."\n");
    exit(1);
  }
}

///// src/_Private/cli_header.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

const string CLI_HEADER = <<<'SH'
#!/bin/sh
set -eu

hack_compiler_cli_directory=$(mktemp -d "${TMPDIR:-/tmp}/hack-compiler-cli.XXXXXX")
trap 'rm -rf "$hack_compiler_cli_directory"' 0
trap 'exit 1' HUP INT TERM
tail -n +__SOURCE_LINE__ "$0" > "$hack_compiler_cli_directory/source.resource"

# Quote each argument before rebuilding the two argument lists in POSIX sh.
hack_compiler_cli_quote() {
  hack_compiler_cli_value=$1
  printf "'"
  while case "$hack_compiler_cli_value" in *\'*) true ;; *) false ;; esac; do
    printf '%s' "${hack_compiler_cli_value%%\'*}" "'\\''"
    hack_compiler_cli_value=${hack_compiler_cli_value#*\'}
  done
  printf "%s' " "$hack_compiler_cli_value"
}

hack_compiler_cli_mode=script
hack_compiler_cli_hhvm_arguments=
hack_compiler_cli_script_arguments=
for hack_compiler_cli_argument in "$@"; do
  case "$hack_compiler_cli_mode:$hack_compiler_cli_argument" in
    script:--hhvm-args) hack_compiler_cli_mode=hhvm ;;
    hhvm:--) hack_compiler_cli_mode=remaining ;;
    hhvm:*)
      hack_compiler_cli_hhvm_arguments="$hack_compiler_cli_hhvm_arguments$(hack_compiler_cli_quote "$hack_compiler_cli_argument")"
      ;;
    *)
      hack_compiler_cli_script_arguments="$hack_compiler_cli_script_arguments$(hack_compiler_cli_quote "$hack_compiler_cli_argument")"
      ;;
  esac
done
eval "set -- $hack_compiler_cli_hhvm_arguments \"\$hack_compiler_cli_directory/source.resource\" $hack_compiler_cli_script_arguments"
hhvm "$@"
SH;

///// src/_Private/compile_resource.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{Dict, Str};

function compile_resource(dict<string, string> $sources)[]: string {
  return Dict\map_with_key(
    $sources,
    ($path, $source) ==>
      Str\format("///// %s /////\n%s", $path, rewrite_source($source)),
  )
    |> Str\join($$, "\n");
}

///// src/_Private/format_source_async.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{File, Str, Vec};
use function escapeshellarg, exec;

async function format_source_async(
  string $source,
)[defaults]: Awaitable<string> {
  using $input = File\temporary_file();
  using $output = File\temporary_file();
  await $input->getHandle()->writeAllAsync($source);
  $diagnostics = vec[];
  $status = 0;
  exec(
    'hackfmt --format-generated-code < '.
    escapeshellarg($input->getHandle()->getPath()).
    ' 2>&1 > '.
    escapeshellarg($output->getHandle()->getPath()),
    inout $diagnostics,
    inout $status,
  );
  invariant(
    $status === 0,
    "Could not format Hack source:\n%s",
    Str\join(
      Vec\map(to_mixed($diagnostics) as vec<_>, $line ==> $line as string),
      "\n",
    ),
  );
  return await $output->getHandle()->readAllAsync();
}

///// src/_Private/obsolete_server_header.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

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

///// src/_Private/rewrite_source.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{C, Str, Vec};

function rewrite_source(string $source)[]: string {
  if (Str\starts_with($source, '#!')) {
    $newline = Str\search($source, "\n");
    $source = $newline is nonnull ? Str\slice($source, $newline + 1) : '';
  }
  $script = ast_parse_script($source);
  $namespaces = Vec\filter(ast_declarations($script), ast_is_namespace<>);
  $namespace = C\find($namespaces, ast_is_file_scoped_namespace<>);
  if ($namespace is null) {
    return $source;
  }
  $name_tokens = ast_namespace_name_tokens($namespace);
  if (C\is_empty($name_tokens)) {
    return $source;
  }
  $name_start = ast_token_text_start(C\firstx($name_tokens));
  $name_end = ast_token_text_end(C\lastx($name_tokens));
  $name = Str\slice($source, $name_start, $name_end - $name_start);

  $keyword = ast_namespace_keyword_token($namespace);
  $semicolon = ast_namespace_semicolon_token($namespace);
  $start = ast_token_text_start($keyword);
  $end = ast_token_end($semicolon);
  // Keep the license and other leading trivia; discard the namespace's trailing trivia.
  $remaining = Str\slice($source, 0, $start).Str\slice($source, $end);
  return Str\format("namespace %s;\n%s\n", $name, Str\trim($remaining, "\n"));
}

///// src/_Private/server_header.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

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

///// src/_Private/source_files.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{C, File, Str, Vec};
use type FilesystemIterator, SplFileInfo;
use function is_dir, is_file;

async function load_file_async(
  string $path,
  string $cwd,
)[defaults]: Awaitable<(string, string)> {
  $file = File\open_read_only($path);
  using $file->closeWhenDisposed();
  using $file->tryLockx(File\LockType::SHARED);
  return tuple(relative_path($path, $cwd), await $file->readAllAsync());
}

function relative_path(string $path, string $cwd)[]: string {
  $parts = Str\split($path, '/') |> Vec\filter($$, $part ==> $part !== '');
  $base = Str\split($cwd, '/') |> Vec\filter($$, $part ==> $part !== '');
  $common = 0;
  while (
    $common < C\count($parts) &&
    $common < C\count($base) &&
    $parts[$common] === $base[$common]
  ) {
    ++$common;
  }
  return Str\repeat('../', C\count($base) - $common).
    Str\join(Vec\drop($parts, $common), '/');
}

function source_paths(
  string $path,
  vec<string> $excludes,
)[defaults]: vec<string> {
  if (C\any($excludes, $prefix ==> Str\starts_with($path, $prefix))) {
    return vec[];
  }
  if (is_file($path)) {
    return vec[$path];
  }
  invariant(is_dir($path), 'Not a file or directory: %s', $path);
  $paths = vec[];
  foreach (
    new FilesystemIterator($path, FilesystemIterator::SKIP_DOTS) as $file
  ) {
    $file = to_mixed($file) as SplFileInfo;
    if (
      ($file->isDir() && !$file->isLink()) ||
      ($file->isFile() && $file->getExtension() === 'hack')
    ) {
      $paths =
        Vec\concat($paths, source_paths($file->getPathname(), $excludes));
    }
  }
  return $paths;
}

///// src/_Private/to_mixed.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

function to_mixed(mixed $mixed)[]: mixed {
  return $mixed;
}

///// src/_Private/typecheck_resource_async.hack /////
namespace HTL\HackCompiler\_Private;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{File, OS, Str, Vec};
use function escapeshellarg, exec, is_file, rmdir, sys_get_temp_dir, unlink;

/** Check a compiled resource in an isolated, temporary Hack project. */
async function typecheck_resource_async(
  string $resource,
)[defaults]: Awaitable<void> {
  $directory = OS\mkdtemp(sys_get_temp_dir().'/hack-compiler.XXXXXX');
  $source_path = $directory.'/source.hack';
  $config_path = $directory.'/.hhconfig';
  try {
    $source = File\open_write_only($source_path);
    using ($source->closeWhenDisposed()) {
      await $source->writeAllAsync($resource);
    }
    $config = File\open_write_only($config_path);
    using ($config->closeWhenDisposed()) {
      await $config->writeAllAsync('');
    }
    $output = vec[];
    $status = 0;
    exec(
      'hh_server --check --config use_watchman=false '.
      escapeshellarg($directory).
      ' 2>&1',
      inout $output,
      inout $status,
    );
    invariant(
      $status === 0,
      "Resource typecheck failed:\n%s",
      Str\join(
        Vec\map(to_mixed($output) as vec<_>, $line ==> $line as string),
        "\n",
      ),
    );
  } finally {
    if (is_file($source_path)) {
      unlink($source_path);
    }
    if (is_file($config_path)) {
      unlink($config_path);
    }
    rmdir($directory);
  }
}

///// src/compile.hack /////
namespace HTL\HackCompiler;
/** hack-compiler is MIT licensed, see /LICENSE. */

/** Compile paths and source texts in insertion order. */
function compile(dict<string, string> $sources, CompileMode $mode)[]: string {
  return wrap_resource(_Private\compile_resource($sources), $mode);
}

///// src/compile_roots_async.hack /////
namespace HTL\HackCompiler;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{C, Dict, Str, Vec};
use function getcwd;

/** Compile absolute source roots, with markers relative to the current directory. */
async function compile_roots_async(
  vec<string> $roots,
  vec<string> $excludes,
  CompileMode $mode,
  bool $typecheck = false,
)[defaults]: Awaitable<string> {
  invariant(
    C\every(
      Vec\concat($roots, $excludes),
      $path ==> Str\starts_with($path, '/'),
    ),
    'Roots and exclude prefixes must be absolute paths.',
  );
  $cwd = getcwd() as string;
  $paths = Vec\map($roots, $root ==> _Private\source_paths($root, $excludes))
    |> Vec\flatten($$);
  $sources = await Vec\map_async(
    keyset($paths),
    $path ==> _Private\load_file_async($path, $cwd),
  );
  $files = Dict\from_entries($sources) |> Dict\sort_by_key($$);
  invariant(!C\is_empty($files), 'No files selected for compilation.');
  $resource = _Private\compile_resource($files);
  if ($typecheck) {
    await _Private\typecheck_resource_async($resource);
  }
  return wrap_resource($resource, $mode);
}

///// src/sign_source.hack /////
namespace HTL\HackCompiler;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\Str;
use function sha1;

/** Fill an empty Pragma digest with the compatible 20-character SHA-1 signature. */
function sign_source(string $source)[]: string {
  $token = _Private\ast_digest_token(
    _Private\ast_parse_script($source),
    Str\contains($source, 'use type HTL\\Pragma\\Pragmas;'),
    Str\contains($source, 'use function HTL\\Pragma\\pragma;'),
  );
  invariant(
    $token is nonnull,
    'Source must contain a PhaLinters digest pragma.',
  );
  invariant(
    Str\trim(_Private\ast_token_text($token), "\"'") === 'digest:',
    'Source is already signed.',
  );
  $offset = _Private\ast_token_text_start($token) + 1 + Str\length('digest:');
  $digest = Str\slice(sha1($source) as string, 0, 20);
  return Str\slice($source, 0, $offset).$digest.Str\slice($source, $offset);
}

///// src/wrap_resource.hack /////
namespace HTL\HackCompiler;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\{C, Str};

/** Wrap an already compiled resource for the selected output mode. */
function wrap_resource(string $resource, CompileMode $mode)[]: string {
  switch ($mode) {
    case CompileMode::RESOURCE:
      return $resource;
    case CompileMode::CLI:
      $header = _Private\CLI_HEADER;
      break;
    case CompileMode::SERVER:
      $header = _Private\SERVER_HEADER;
      break;
    case CompileMode::SERVER_OBSOLETE:
      $header = _Private\OBSOLETE_SERVER_HEADER;
      break;
  }
  $header .= "\nexit 0\n__HACK_COMPILER_RESOURCE__\n";
  $source_line = C\count(Str\split($header, "\n"));
  return
    Str\replace($header, '__SOURCE_LINE__', (string)$source_line).$resource;
}

///// src/write_source_async.hack /////
namespace HTL\HackCompiler;
/** hack-compiler is MIT licensed, see /LICENSE. */

use namespace HH\Lib\File;

/** Prepare the complete source before opening the destination for writing. */
async function write_source_async(
  string $source,
  string $path,
  shape(?'format' => bool, ?'sign' => bool /*_*/) $options = shape(),
)[defaults]: Awaitable<void> {
  if (Shapes::idx($options, 'format', true)) {
    $source = await _Private\format_source_async($source);
  }
  if (Shapes::idx($options, 'sign', true)) {
    $source = sign_source($source);
  }
  $file = File\open_write_only($path);
  using ($file->closeWhenDisposed()) {
    using ($file->tryLockx(File\LockType::EXCLUSIVE)) {
      $file->truncate(0);
      await $file->writeAllAsync($source);
    }
  }
}
