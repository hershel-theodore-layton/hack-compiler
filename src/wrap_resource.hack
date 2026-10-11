/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

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
