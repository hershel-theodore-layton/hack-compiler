/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

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
