/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

use namespace HH\Lib\{Str, Vec};
use type HTL\HackCompiler\CompileMode;

function rewrite_server_paths(string $source, CompileMode $mode)[]: string {
  if ($mode !== CompileMode::SERVER && $mode !== CompileMode::SERVER_OBSOLETE) {
    return $source;
  }
  // Replacing unbraced interpolated members can silently become literal text.
  $tokens = ast_tokens(
    ast_parse_script($source),
    keyset['embedded_member_selection_expression'],
  );
  foreach (Vec\reverse($tokens) as $token) {
    if (sub_string($token, 'kind') !== 'name') {
      continue;
    }
    $text = Str\uppercase(ast_token_text($token));
    if ($text !== '__DIR__' && $text !== '__FILE__') {
      continue;
    }
    $replacement = "(\\getenv('HACK_COMPILER_SERVER_FILE') as string)";
    if ($text === '__DIR__') {
      $replacement = '\\dirname('.$replacement.')';
    }
    $source = Str\slice($source, 0, ast_token_text_start($token)).
      $replacement.
      Str\slice($source, ast_token_text_end($token));
  }
  return $source;
}
