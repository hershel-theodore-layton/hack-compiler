/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

async function process_source_file_async(
  string $source,
  shape(?'format' => bool, ?'sign' => bool, ...) $options = shape(),
)[defaults]: Awaitable<string> {
  if (Shapes::idx($options, 'format', true)) {
    $source = await _Private\format_source_async($source);
  }
  if (Shapes::idx($options, 'sign', true)) {
    $source = sign_source($source);
  }
  return $source;
}
