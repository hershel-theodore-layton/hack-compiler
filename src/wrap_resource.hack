/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

use namespace HH\Lib\{C, Str, Vec};
use function gzencode;

/** Wrap an already compiled resource for the selected output mode. */
function wrap_resource(
  string $resource,
  CompileMode $mode,
  bool $replace = false,
  bool $compressed = false,
  vec<string> $default_hhvm_args = vec[],
)[]: string {
  invariant(
    !$compressed || $mode !== CompileMode::RESOURCE,
    '--compressed requires a shell launcher mode (cli, server, server-obsolete).',
  );
  invariant(
    C\is_empty($default_hhvm_args) || $mode !== CompileMode::RESOURCE,
    '--default-hhvm-arg requires a shell launcher mode (cli, server, server-obsolete).',
  );
  $resource = _Private\prepare_server_resource($resource, $mode, $replace);
  switch ($mode) {
    case CompileMode::RESOURCE:
      return $resource;
    case CompileMode::CLI:
      $header = _Private\CLI_HEADER;
      break;
    case CompileMode::SERVER:
      $header = _Private\SERVER_OPTIONS;
      break;
    case CompileMode::SERVER_OBSOLETE:
      $header = _Private\OBSOLETE_SERVER_OPTIONS;
      break;
  }
  if ($mode === CompileMode::SERVER || $mode === CompileMode::SERVER_OBSOLETE) {
    $header =
      Str\replace($header, '__SERVER_ARGUMENTS__', _Private\SERVER_ARGUMENTS);
    if ($replace) {
      $header = Str\replace($header, 'replace=no', 'replace=yes');
    }
    $header .= "\n".
      _Private\SERVER_PREPARE_RUNTIME.
      "\n".
      ($replace ? _Private\SERVER_REPLACE_RUNTIME."\n" : '').
      _Private\SERVER_RUNTIME;
  }
  // Quote each argv element, then quote the complete serialized list for assignment.
  $quote = (string $value) ==> "'".Str\replace($value, "'", "'\\''")."'";
  $defaults = Vec\map($default_hhvm_args, $quote) |> Str\join($$, ' ');
  if ($compressed) {
    // The shell exits before parsing the binary payload.
    $header = Str\replace(
      $header,
      'tail -n +__SOURCE_LINE__ "$0" > ',
      'hack_compiler_extract "$0" ',
    );
    $header =
      Str\replace($header, 'set -eu', "set -eu\n"._Private\COMPRESSED_EXTRACT);
    $resource = gzencode($resource, 9) as string;
  }
  $header .= "\nexit 0\n__HACK_COMPILER_RESOURCE__\n";
  $source_line =
    C\count(Str\split($header, "\n")) + C\count(Str\split($defaults, "\n")) - 1;
  $header = Str\replace($header, '__SOURCE_LINE__', (string)$source_line);
  // Insert defaults last so template replacements cannot alter argument values.
  return Str\replace($header, '__DEFAULT_HHVM_ARGUMENTS__', $quote($defaults)).
    $resource;
}
