/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\Tests;

use namespace HH;
use namespace HH\Lib\Str;
use namespace HTL\HackCompiler;

<<__EntryPoint>>
function main()[defaults]: void {
  $cases = dict[
    'no namespace' => tuple(
      "// license\nfunction f()[]: void {}\n",
      "// license\nfunction f()[]: void {}\n",
    ),
    'executable source' => tuple(
      "#!/usr/bin/env hhvm\nnamespace Example;\nconst int X = 1;\n",
      "namespace Example;\nconst int X = 1;\n",
    ),
    'file namespace' => tuple(
      "// license\nnamespace Example;\nfunction f()[]: void {}\n",
      "namespace Example;\n// license\nfunction f()[]: void {}\n",
    ),
    'trailing namespace comment' => tuple(
      "// license\nnamespace Example; // removed\n\nfunction f()[]: void {}\n\n",
      "namespace Example;\n// license\n\nfunction f()[]: void {}\n",
    ),
    'namespace name trivia' => tuple(
      "namespace Foo /* keep */ \\ Bar;\nfunction f()[]: void {}",
      "namespace Foo /* keep */ \\ Bar;\nfunction f()[]: void {}\n",
    ),
    'unicode byte offsets' => tuple(
      "/** café 🐱 */\nnamespace Example;\nconst string TEXT = 'é';\n",
      "namespace Example;\n/** café 🐱 */\nconst string TEXT = 'é';\n",
    ),
    'CRLF bytes' => tuple(
      "// license\r\nnamespace Example;\r\nconst int X = 1;\r\n",
      "namespace Example;\n// license\r\nconst int X = 1;\r\n",
    ),
    'namespace block' => tuple(
      "namespace Example { const int X = 1; }\n",
      "namespace Example { const int X = 1; }\n",
    ),
    'multiple file namespaces' => tuple(
      "// license\nnamespace A;\nconst int X = 1;\nnamespace B;\nconst int X = 2;\nnamespace A;\nconst int Y = 3;\n",
      "namespace A;\n// license\nconst int X = 1;\nnamespace B;\nconst int X = 2;\nnamespace A;\nconst int Y = 3;\n",
    ),
    'opening tag' => tuple(
      "<?hh\n// license\nnamespace Example;\nconst int X = 1;\n",
      "namespace Example;\n<?hh\n// license\nconst int X = 1;\n",
    ),
    'namespace only' => tuple("namespace Example;\n", "namespace Example;\n\n"),
  ];
  foreach ($cases as $name => list($source, $expected)) {
    $actual = HackCompiler\compile(
      dict['example.hack' => $source],
      HackCompiler\CompileMode::RESOURCE,
    );
    HH\invariant(
      $actual === "///// example.hack /////\n".$expected,
      'Failed byte comparison: %s',
      $name,
    );
  }
  HH\invariant(
    HackCompiler\compile(dict[], HackCompiler\CompileMode::RESOURCE) === '',
    'Empty input must produce no bytes.',
  );
  $ordered = HackCompiler\compile(
    dict[
      'z.hack' => "const int Z = 1;\n",
      'a.hack' => "const int A = 2;\n",
    ],
    HackCompiler\CompileMode::RESOURCE,
  );
  HH\invariant(
    $ordered ===
      "///// z.hack /////\nconst int Z = 1;\n\n///// a.hack /////\nconst int A = 2;\n",
    'Input order and separator bytes must be preserved.',
  );
  $xhp = 'function markup(): mixed { '.
    'return <__FILE__ __DIR__="__FILE__">__DIR__ {__FILE__}</__FILE__>; }';
  $server = HackCompiler\compile(
    dict['markup.hack' => $xhp],
    HackCompiler\CompileMode::SERVER,
  );
  HH\invariant(
    Str\contains($server, '<__FILE__ __DIR__="__FILE__">__DIR__ {') &&
      Str\contains($server, '</__FILE__>') &&
      !Str\contains($server, '{__FILE__}'),
    'Literal XHP content must stay unchanged, but embedded code is rewritten.',
  );
  $interpolation =
    'function text(O $o): string { '.'return "__DIR__ $o->__FILE__"; }';
  HH\invariant(
    Str\contains(
      HackCompiler\compile(
        dict['text.hack' => $interpolation],
        HackCompiler\CompileMode::SERVER,
      ),
      $interpolation,
    ),
    'Unbraced string interpolation must not become literal replacement text.',
  );
  $chain =
    'function chain(C $c): mixed { '.'return $c->a(__FILE__)->b(__DIR__); }';
  $server = HackCompiler\compile(
    dict['chain.hack' => $chain],
    HackCompiler\CompileMode::SERVER,
  );
  HH\invariant(
    !Str\contains($server, 'a(__FILE__)') &&
      !Str\contains($server, 'b(__DIR__)'),
    'Arguments within chained calls must be rewritten.',
  );
  $constants = 'const string FILE = __FILE__; '.
    'class Paths { public string $path = __DIR__; } '.
    'enum PathsEnum: string { VALUE = __FILE__; } '.
    '<<Attr(__DIR__)>> function defaults(string $path = __FILE__): void {} '.
    "function shape_key(): mixed { return shape(__DIR__ => 'value'); }";
  $server = HackCompiler\compile(
    dict['constants.hack' => $constants],
    HackCompiler\CompileMode::SERVER,
  );
  HH\invariant(
    !Str\contains($server, '__FILE__') && !Str\contains($server, '__DIR__'),
    'Constant expression contexts must also be rewritten.',
  );
  echo "Byte-level compiler checks passed.\n";
}
