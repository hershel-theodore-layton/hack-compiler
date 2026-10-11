/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

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
