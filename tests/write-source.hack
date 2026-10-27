/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\Tests\WriteSource;

use namespace HH\Lib\{File, Str};
use namespace HTL\HackCompiler;
use type Exception;
use function sha1;

<<__EntryPoint>>
async function main_async()[defaults]: Awaitable<void> {
  $source = "namespace Example;\nuse type HTL\\Pragma\\Pragmas;\n".
    "<<file: Pragmas(vec['PhaLinters', 'digest:'])>>\n".
    "const string DECOY='digest:';\n";
  $digest = Str\slice(sha1($source) as string, 0, 20);
  $expected = Str\replace($source, "'digest:'])", "'digest:".$digest."'])");
  invariant(
    HackCompiler\sign_source($source) === $expected,
    'Signature bytes differ.',
  );
  $directive = "namespace Example;\nuse function HTL\\Pragma\\pragma;\n".
    "function example(): void { pragma('HTL\\PhaLinters', 'digest:'); }\n";
  invariant(
    HackCompiler\sign_source($directive) ===
      Str\replace(
        $directive,
        "'digest:'",
        "'digest:".Str\slice(sha1($directive) as string, 0, 20)."'",
      ),
    'Function directive signature differs.',
  );
  foreach (vec['', "namespace Example;\n"] as $preamble) {
    invariant(
      HackCompiler\prepare_signing_preamble($preamble) ===
        $preamble.
        "\nuse type HTL\\Pragma\\Pragmas;\n".
        "\n<<file: Pragmas(vec['PhaLinters', 'digest:'])>>\n",
      'The import must precede a new attribute.',
    );
  }
  $unimported =
    "namespace Example;\n"."<<file: Pragmas(vec['Other', 'keep'])>>\n";
  invariant(
    HackCompiler\prepare_signing_preamble($unimported) ===
      "namespace Example;\n\nuse type HTL\\Pragma\\Pragmas;\n".
      "<<file: Pragmas(vec['PhaLinters', 'digest:'], vec['Other', 'keep'])>>\n",
    'The import must precede an existing attribute.',
  );
  foreach (
    vec[
      '',
      "namespace Example;\n// Pragmas( and 'digest:' are documentation",
      "namespace Example;\nconst string DOC = \"Pragmas( 'digest:'\";",
      "namespace Example;\nuse type HTL\\Pragma\\Pragmas;\n".
      '<<file: Pragmas()>>',
      "namespace Example;\nuse type HTL\\Pragma\\Pragmas;\n".
      "<<file: Pragmas(/* keep */ vec['Other', 'keep'])>>",
      $source,
      Str\replace(
        $source,
        "'PhaLinters', 'digest:'",
        '"PhaLinters", "digest:"',
      ),
    ] as $preamble
  ) {
    $prepared = HackCompiler\prepare_signing_preamble($preamble);
    invariant(
      HackCompiler\prepare_signing_preamble($prepared) === $prepared,
      'Preparing a preamble must be idempotent.',
    );
    $signed = HackCompiler\sign_source($prepared);
    invariant($signed !== $prepared, 'Prepared preamble must be signable.');
    invariant(
      HackCompiler\prepare_signing_preamble($signed) === $signed,
      'Preparing a preamble must preserve an existing signature.',
    );
  }
  using $destination = File\temporary_file();
  $path = $destination->getHandle()->getPath();
  await HackCompiler\write_source_async($source, $path);
  $formatted_signed = await read_source_async($path);
  invariant(
    !Str\contains($formatted_signed, "DECOY='digest:'"),
    'Source was not formatted.',
  );
  // Extract only the embedded signature, leaving the decoy unchanged.
  $parts = Str\split($formatted_signed, 'digest:');
  $embedded = Str\slice($parts[1], 0, 20);
  $unsigned = Str\replace($formatted_signed, 'digest:'.$embedded, 'digest:');
  invariant(
    HackCompiler\sign_source($unsigned) === $formatted_signed,
    'Signing must follow formatting.',
  );
  $failed = false;
  try {
    await HackCompiler\write_source_async(
      $formatted_signed,
      $path,
      shape('format' => false),
    );
  } catch (Exception $_) {
    $failed = true;
  }
  invariant($failed, 'Already signed source must be rejected.');
  echo "Source writing checks passed.\n";
}

async function read_source_async(string $path)[defaults]: Awaitable<string> {
  $file = File\open_read_only($path);
  using $file->closeWhenDisposed();
  return await $file->readAllAsync();
}
