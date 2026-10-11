/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

use namespace HH\Lib\{C, Str, Vec};

function rewrite_source(string $source)[]: string {
  if (Str\starts_with($source, '#!')) {
    $newline = Str\search($source, "\n");
    $source = $newline is nonnull ? Str\slice($source, $newline + 1) : '';
  }
  $script = ast_parse_script($source);
  $namespaces = Vec\filter(ast_declarations($script), ast_is_namespace<>);
  $namespace = C\find($namespaces, ast_is_file_scoped_namespace<>);
  if ($namespace is null) {
    return $source;
  }
  $name_tokens = ast_namespace_name_tokens($namespace);
  if (C\is_empty($name_tokens)) {
    return $source;
  }
  $name_start = ast_token_text_start(C\firstx($name_tokens));
  $name_end = ast_token_text_end(C\lastx($name_tokens));
  $name = Str\slice($source, $name_start, $name_end - $name_start);

  $keyword = ast_namespace_keyword_token($namespace);
  $semicolon = ast_namespace_semicolon_token($namespace);
  $start = ast_token_text_start($keyword);
  $end = ast_token_end($semicolon);
  // Keep the license and other leading trivia; discard the namespace's trailing trivia.
  $remaining = Str\slice($source, 0, $start).Str\slice($source, $end);
  return Str\format("namespace %s;\n%s\n", $name, Str\trim($remaining, "\n"));
}
