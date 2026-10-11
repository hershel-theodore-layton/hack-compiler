/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\Tests;

use namespace HH;
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
  echo "Byte-level compiler checks passed.\n";
}
