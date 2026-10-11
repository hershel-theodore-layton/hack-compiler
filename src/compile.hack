/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

/** Compile paths and source texts in insertion order. */
function compile(dict<string, string> $sources, CompileMode $mode)[]: string {
  return wrap_resource(_Private\compile_resource($sources), $mode);
}
