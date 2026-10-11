/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

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
