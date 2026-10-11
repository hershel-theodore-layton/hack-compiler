/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler;

enum CompileMode: string {
  CLI = 'cli';
  RESOURCE = 'resource';
  SERVER = 'server';
  SERVER_OBSOLETE = 'server-obsolete';
}
