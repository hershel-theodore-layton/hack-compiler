/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string SERVER_ARGUMENTS = <<<'SH'
# Quote each argument before rebuilding the two argument lists in POSIX sh.
hack_compiler_server_quote() {
  hack_compiler_server_value=$1
  printf "'"
  while case "$hack_compiler_server_value" in *\'*) true ;; *) false ;; esac; do
    printf '%s' "${hack_compiler_server_value%%\'*}" "'\\''"
    hack_compiler_server_value=${hack_compiler_server_value#*\'}
  done
  printf "%s' " "$hack_compiler_server_value"
}

hack_compiler_server_mode=launcher
hack_compiler_server_hhvm_arguments=
hack_compiler_server_launcher_arguments=
for hack_compiler_server_argument in "$@"; do
  case "$hack_compiler_server_mode:$hack_compiler_server_argument" in
    launcher:--hhvm-args) hack_compiler_server_mode=hhvm ;;
    hhvm:--) hack_compiler_server_mode=remaining ;;
    hhvm:*)
      hack_compiler_server_hhvm_arguments="$hack_compiler_server_hhvm_arguments$(hack_compiler_server_quote "$hack_compiler_server_argument")"
      ;;
    *)
      hack_compiler_server_launcher_arguments="$hack_compiler_server_launcher_arguments$(hack_compiler_server_quote "$hack_compiler_server_argument")"
      ;;
  esac
done
eval "set -- $hack_compiler_server_launcher_arguments"
SH;
