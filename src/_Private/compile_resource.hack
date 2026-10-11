/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

use namespace HH\Lib\{Dict, Str};

function compile_resource(dict<string, string> $sources)[]: string {
  return Dict\map_with_key(
    $sources,
    ($path, $source) ==>
      Str\format("///// %s /////\n%s", $path, rewrite_source($source)),
  )
    |> Str\join($$, "\n");
}
