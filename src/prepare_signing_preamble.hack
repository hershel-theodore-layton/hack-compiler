/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

use namespace HH\Lib\{C, Str};

/**
 * Ensure a canonical Pragmas file attribute contains a signing placeholder.
 * Accepts a preamble with a file-scoped namespace, before generated declarations.
 * Preserves existing digests; sign_source() still rejects already signed input.
 */
function prepare_signing_preamble(string $preamble)[]: string {
  $script = _Private\ast_parse_script($preamble);
  $has_import = false;
  $has_digest = false;
  $insert_at = null;
  $import_at = null;
  $separator = '';
  foreach (_Private\ast_declarations($script) as $node) {
    $kind = _Private\sub_string($node, 'kind');
    if ($kind === 'namespace_use_declaration') {
      $has_import = $has_import ||
        _Private\ast_node_text($node) === 'usetypeHTL\\Pragma\\Pragmas;';
    }
    if ($kind !== 'file_attribute_specification') {
      continue;
    }
    $attributes =
      _Private\sub_array($node, 'file_attribute_specification_attributes');
    foreach (_Private\ast_list_items($attributes) as $attribute) {
      if (
        _Private\sub_string($attribute, 'kind') !== 'constructor_call' ||
        _Private\ast_node_text(
          _Private\sub_array($attribute, 'constructor_call_type'),
        ) !==
          'Pragmas'
      ) {
        continue;
      }
      $import_at ??=
        _Private\ast_token_text_start(C\firstx(_Private\ast_tokens($node)));
      $arguments = _Private\ast_list_items(
        _Private\sub_array($attribute, 'constructor_call_argument_list'),
      );
      if ($insert_at is null) {
        $open = _Private\sub_array(
          $attribute,
          'constructor_call_left_paren',
          'token',
        );
        $insert_at = _Private\ast_token_text_end($open);
        $separator = C\is_empty($arguments) ? '' : ', ';
      }
      foreach ($arguments as $argument) {
        if (
          _Private\sub_string($argument, 'kind') ===
            'vector_intrinsic_expression'
        ) {
          $has_digest = $has_digest ||
            _Private\ast_digest_arguments_token(
              _Private\sub_array($argument, 'vector_intrinsic_members'),
            ) is nonnull;
        }
      }
    }
  }
  if (!$has_digest && $insert_at is nonnull) {
    $preamble = Str\slice($preamble, 0, $insert_at).
      "vec['PhaLinters', 'digest:']".
      $separator.
      Str\slice($preamble, $insert_at);
  }
  if (!$has_import) {
    $import = "\nuse type HTL\\Pragma\\Pragmas;\n";
    $preamble = $import_at is nonnull
      ? Str\slice($preamble, 0, $import_at).
        $import.
        Str\slice($preamble, $import_at)
      : $preamble.$import;
  }
  if (!$has_digest && $insert_at is null) {
    $preamble .= "\n<<file: Pragmas(vec['PhaLinters', 'digest:'])>>\n";
  }
  return $preamble;
}
