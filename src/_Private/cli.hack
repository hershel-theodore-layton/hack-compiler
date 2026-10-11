/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

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
