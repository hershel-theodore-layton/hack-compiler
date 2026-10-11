/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

use namespace HH;
use namespace HH\Lib\{C, Dict, Str, Vec};

function ast_declarations(
  AnyArray<arraykey, mixed> $script,
)[]: AnyArray<arraykey, AnyArray<arraykey, mixed>> {
  $declarations = sub_array($script, 'script_declarations');
  return sub_arrays($declarations, 'elements');
}

function ast_digest_arguments_token(
  AnyArray<arraykey, mixed> $arguments,
)[]: ?AnyArray<arraykey, mixed> {
  $items = ast_list_items($arguments);
  if (
    C\count($items) !== 2 ||
    sub_string($items[0], 'kind') !== 'literal' ||
    sub_string($items[1], 'kind') !== 'literal'
  ) {
    return null;
  }
  $name = Str\trim(ast_node_text($items[0]), "\"'");
  $digest = Str\trim(ast_node_text($items[1]), "\"'");
  if (
    ($name !== 'PhaLinters' && $name !== 'HTL\\PhaLinters') ||
    !Str\starts_with($digest, 'digest:')
  ) {
    return null;
  }
  return sub_array($items[1], 'literal_expression', 'token');
}

/** Locate the first PhaLinters digest directive using the Pragma syntax. */
function ast_digest_token(
  AnyArray<arraykey, mixed> $script,
  bool $attributes,
  bool $directives,
)[]: ?AnyArray<arraykey, mixed> {
  if ($attributes) {
    foreach (ast_nodes_of_kind($script, 'constructor_call') as $call) {
      if (
        ast_node_text(sub_array($call, 'constructor_call_type')) !== 'Pragmas'
      ) {
        continue;
      }
      foreach (
        ast_list_items(sub_array($call, 'constructor_call_argument_list')) as
          $argument
      ) {
        if (sub_string($argument, 'kind') !== 'vector_intrinsic_expression') {
          continue;
        }
        $token = ast_digest_arguments_token(
          sub_array($argument, 'vector_intrinsic_members'),
        );
        if ($token is nonnull) {
          return $token;
        }
      }
    }
  }
  if ($directives) {
    foreach (ast_nodes_of_kind($script, 'function_call_expression') as $call) {
      if (
        ast_node_text(sub_array($call, 'function_call_receiver')) !== 'pragma'
      ) {
        continue;
      }
      $token = ast_digest_arguments_token(
        sub_array($call, 'function_call_argument_list'),
      );
      if ($token is nonnull) {
        return $token;
      }
    }
  }
  return null;
}

function ast_is_file_scoped_namespace(
  AnyArray<arraykey, mixed> $namespace,
)[]: bool {
  return
    sub_string($namespace, 'namespace_body', 'kind') === 'namespace_empty_body';
}

function ast_is_namespace(AnyArray<arraykey, mixed> $node)[]: bool {
  return sub_string($node, 'kind') === 'namespace_declaration';
}

function ast_list_items(
  AnyArray<arraykey, mixed> $node,
)[]: vec<AnyArray<arraykey, mixed>> {
  if (sub_string($node, 'kind') === 'missing') {
    return vec[];
  }
  return Vec\map(
    sub_arrays($node, 'elements'),
    $item ==> sub_array($item, 'list_item'),
  );
}

function ast_namespace_keyword_token(
  AnyArray<arraykey, mixed> $namespace,
)[]: AnyArray<arraykey, mixed> {
  $header = sub_array($namespace, 'namespace_header');
  return sub_array($header, 'namespace_keyword', 'token');
}

function ast_namespace_name_tokens(
  AnyArray<arraykey, mixed> $namespace,
)[]: vec<AnyArray<arraykey, mixed>> {
  $header = sub_array($namespace, 'namespace_header');
  return ast_tokens(sub_array($header, 'namespace_name'));
}

function ast_namespace_semicolon_token(
  AnyArray<arraykey, mixed> $namespace,
)[]: AnyArray<arraykey, mixed> {
  return
    sub_array($namespace, 'namespace_body', 'namespace_semicolon', 'token');
}

function ast_node_text(AnyArray<arraykey, mixed> $node)[]: string {
  return Str\join(Vec\map(ast_tokens($node), ast_token_text<>), '');
}

/** Descendants in source order, including the node itself. */
function ast_nodes_of_kind(
  AnyArray<arraykey, mixed> $node,
  string $kind,
)[]: vec<AnyArray<arraykey, mixed>> {
  $node_kind = sub_string($node, 'kind');
  if ($node_kind === 'token' || $node_kind === 'missing') {
    return vec[];
  }
  $children = $node_kind === 'list'
    ? sub_array($node, 'elements')
    : Dict\filter_keys($node, $key ==> $key !== 'kind');
  $descendants = Vec\map(
    $children,
    $child ==> ast_nodes_of_kind($child as AnyArray<_, _>, $kind),
  )
    |> Vec\flatten($$);
  return
    $node_kind === $kind ? Vec\concat(vec[$node], $descendants) : $descendants;
}

function ast_parse_script(string $source)[]: AnyArray<arraykey, mixed> {
  $parsed = HH\ffp_parse_string($source) as AnyArray<_, _>;
  return sub_array($parsed, 'parse_tree');
}

function ast_token_end(AnyArray<arraykey, mixed> $token)[]: int {
  return ast_token_text_end($token) + sub_int($token, 'trailing_width');
}

function ast_token_text(AnyArray<arraykey, mixed> $token)[]: string {
  return sub_string($token, 'text');
}

function ast_token_text_end(AnyArray<arraykey, mixed> $token)[]: int {
  return ast_token_text_start($token) + sub_int($token, 'width');
}

function ast_token_text_start(AnyArray<arraykey, mixed> $token)[]: int {
  return sub_int($token, 'offset') + sub_int($token, 'leading_width');
}

/** Token payloads in source order, excluding trivia. */
function ast_tokens(
  AnyArray<arraykey, mixed> $node,
)[]: vec<AnyArray<arraykey, mixed>> {
  switch (sub_string($node, 'kind')) {
    case 'token':
      return vec[sub_array($node, 'token')];
    case 'missing':
      return vec[];
    case 'list':
      $children = sub_array($node, 'elements');
      break;
    default:
      $children = Dict\filter_keys($node, $key ==> $key !== 'kind');
  }
  return Vec\map($children, $child ==> ast_tokens($child as AnyArray<_, _>))
    |> Vec\flatten($$);
}

function sub_array(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: AnyArray<arraykey, mixed> {
  return sub_value($array, ...$keys) as AnyArray<_, _>;
}

function sub_arrays(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: AnyArray<arraykey, AnyArray<arraykey, mixed>> {
  return
    Dict\map(sub_array($array, ...$keys), $value ==> $value as AnyArray<_, _>);
}

function sub_int(AnyArray<arraykey, mixed> $array, arraykey ...$keys)[]: int {
  return sub_value($array, ...$keys) as int;
}

function sub_string(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: string {
  return sub_value($array, ...$keys) as string;
}

function sub_value(
  AnyArray<arraykey, mixed> $array,
  arraykey ...$keys
)[]: mixed {
  $value = $array;
  foreach ($keys as $key) {
    $value = ($value as AnyArray<_, _>)[$key];
  }
  return $value;
}
