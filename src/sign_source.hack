/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

use namespace HH\Lib\Str;
use function sha1;

/** Fill an empty Pragma digest with the compatible 20-character SHA-1 signature. */
function sign_source(string $source)[]: string {
  $token = _Private\ast_digest_token(
    _Private\ast_parse_script($source),
    Str\contains($source, 'use type HTL\\Pragma\\Pragmas;'),
    Str\contains($source, 'use function HTL\\Pragma\\pragma;'),
  );
  invariant(
    $token is nonnull,
    'Source must contain a PhaLinters digest pragma.',
  );
  invariant(
    Str\trim(_Private\ast_token_text($token), "\"'") === 'digest:',
    'Source is already signed.',
  );
  $offset = _Private\ast_token_text_start($token) + 1 + Str\length('digest:');
  $digest = Str\slice(sha1($source) as string, 0, 20);
  return Str\slice($source, 0, $offset).$digest.Str\slice($source, $offset);
}
