/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

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
    await _Private\typecheck_resource_async(
      _Private\rewrite_server_paths($resource, $mode),
    );
  }
  return wrap_resource($resource, $mode);
}
