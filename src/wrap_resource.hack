/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

use namespace HH\Lib\{C, Str};

/** Wrap an already compiled resource for the selected output mode. */
function wrap_resource(
  string $resource,
  CompileMode $mode,
  bool $replace = false,
)[]: string {
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
    if ($replace) {
      $header = Str\replace($header, 'replace=no', 'replace=yes');
    }
    $header .= "\n".
      _Private\SERVER_PREPARE_RUNTIME.
      "\n".
      ($replace ? _Private\SERVER_REPLACE_RUNTIME."\n" : '').
      _Private\SERVER_RUNTIME;
  }
  $header .= "\nexit 0\n__HACK_COMPILER_RESOURCE__\n";
  $source_line = C\count(Str\split($header, "\n"));
  return
    Str\replace($header, '__SOURCE_LINE__', (string)$source_line).$resource;
}
