/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

use namespace HH\Lib\{C, Str, Vec};

function rewrite_server_control(string $source)[]: string {
  $entrypoints = Vec\filter(
    ast_nodes_of_kind(ast_parse_script($source), 'function_declaration'),
    $function ==> C\any(
      ast_nodes_of_kind(
        sub_array($function, 'function_attribute_spec'),
        'constructor_call',
      ),
      $attribute ==>
        ast_node_text(sub_array($attribute, 'constructor_call_type')) ===
          '__EntryPoint',
    ),
  );
  invariant(
    C\count($entrypoints) === 1,
    '--enable-self-update requires exactly one entrypoint.',
  );
  $brace = sub_array(
    C\firstx($entrypoints),
    'function_body',
    'compound_left_brace',
    'token',
  );
  $offset = ast_token_text_end($brace);
  return
    Str\slice($source, 0, $offset).SERVER_CONTROL.Str\slice($source, $offset);
}

const string SERVER_CONTROL = <<<'HACK'

  $hack_compiler_nonce = (\HH\global_get('_GET') as dict<_, _>)['__hack_compiler_handshake'] ?? null;
  if ($hack_compiler_nonce is string) {
    \header('Content-Type: text/plain');
    echo 'hack-compiler/1:'.$hack_compiler_nonce.':'.
      (\readlink('/proc/self/ns/pid') as string).':'.
      (\getenv('HACK_COMPILER_SERVER_INSTANCE') as string).':'.(string)\getmypid();
    exit(0);
  }
HACK;
