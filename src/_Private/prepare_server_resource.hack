/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

use type HTL\HackCompiler\CompileMode;

function prepare_server_resource(
  string $resource,
  CompileMode $mode,
  bool $replace,
)[]: string {
  invariant(
    !$replace ||
      $mode === CompileMode::SERVER ||
      $mode === CompileMode::SERVER_OBSOLETE,
    '--enable-self-update is only supported in server modes.',
  );
  $resource = rewrite_server_paths($resource, $mode);
  return $replace ? rewrite_server_control($resource) : $resource;
}
