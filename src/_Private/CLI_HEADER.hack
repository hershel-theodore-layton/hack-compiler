/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string CLI_HEADER = <<<'SH'
#!/bin/sh
set -eu

hack_compiler_cli_directory=$(mktemp -d "${TMPDIR:-/tmp}/hack-compiler-cli.XXXXXX")
trap 'rm -rf "$hack_compiler_cli_directory"' 0
trap 'exit 1' HUP INT TERM
tail -n +__SOURCE_LINE__ "$0" > "$hack_compiler_cli_directory/source.resource"

# Quote each argument before rebuilding the two argument lists in POSIX sh.
hack_compiler_cli_quote() {
  hack_compiler_cli_value=$1
  printf "'"
  while case "$hack_compiler_cli_value" in *\'*) true ;; *) false ;; esac; do
    printf '%s' "${hack_compiler_cli_value%%\'*}" "'\\''"
    hack_compiler_cli_value=${hack_compiler_cli_value#*\'}
  done
  printf "%s' " "$hack_compiler_cli_value"
}

hack_compiler_cli_mode=script
hack_compiler_cli_hhvm_arguments=
hack_compiler_cli_script_arguments=
for hack_compiler_cli_argument in "$@"; do
  case "$hack_compiler_cli_mode:$hack_compiler_cli_argument" in
    script:--hhvm-args) hack_compiler_cli_mode=hhvm ;;
    hhvm:--) hack_compiler_cli_mode=remaining ;;
    hhvm:*)
      hack_compiler_cli_hhvm_arguments="$hack_compiler_cli_hhvm_arguments$(hack_compiler_cli_quote "$hack_compiler_cli_argument")"
      ;;
    *)
      hack_compiler_cli_script_arguments="$hack_compiler_cli_script_arguments$(hack_compiler_cli_quote "$hack_compiler_cli_argument")"
      ;;
  esac
done
eval "set -- $hack_compiler_cli_hhvm_arguments \"\$hack_compiler_cli_directory/source.resource\" $hack_compiler_cli_script_arguments"
hhvm "$@"
SH;
