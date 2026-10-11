/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

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
