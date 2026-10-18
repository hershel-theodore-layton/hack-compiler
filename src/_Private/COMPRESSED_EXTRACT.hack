/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string COMPRESSED_EXTRACT = <<<'SH'

# Extract the embedded gzip stream without starting another HHVM process.
hack_compiler_extract() {
  tail -n +__SOURCE_LINE__ "$1" | gzip -dc > "$2"
}
SH;
