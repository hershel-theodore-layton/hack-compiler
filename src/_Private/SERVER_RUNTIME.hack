/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string SERVER_RUNTIME = <<<'SH'
if [ "$launch_mode" = daemon ]; then
  set -- "$@" -dhhvm.log.file=/dev/null
fi
eval "set -- \"\$@\" $hack_compiler_server_hhvm_arguments"
if [ "$replace" = no ]; then
  set -- "$@" "-dhhvm.pid_file=$work_dir/www.pid"
fi
start_server() {
  if [ "$launch_mode" = daemon ]; then
    set -- setsid hhvm "$@"
  else
    set -- hhvm "$@"
  fi
  exec "$@" -m server -p "$port" --no-config \
    -vServer.AllowRunAsRoot=1 \
    -vServer.ExitOnBindFail=true \
    -dhhvm.repo.authoritative=true \
    "-dhhvm.repo.path=$work_dir/hhvm.hhbc" \
    "-dhhvm.server.global_document=$resource" \
    "-dhhvm.server.allowed_files[0]=$resource" \
    '-dhhvm.php_file.extensions[resource]=1'
}
if [ "$launch_mode" = daemon ]; then
  start_server "$@" > /dev/null 2>&1 &
else
  start_server "$@" &
fi
server_pid=$!
while :; do
  if [ "$replace" = yes ]; then
    if handshake && [ "$handshake_instance" = "$nonce" ]; then break; fi
  elif [ -s "$work_dir/www.pid" ]; then
    if [ "$launch_mode" != daemon ] ||
       curl --noproxy '*' --silent --head --max-time 1 \
         "http://127.0.0.1:$port/" > /dev/null; then
      break
    fi
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"
    exit 1
  fi
  sleep 0.1
done
rm -rf "$work_dir"
if [ "$launch_mode" = daemon ]; then
  server_pid=
  exit 0
fi
server_status=0
wait "$server_pid" || server_status=$?
server_pid=
exit "$server_status"
SH;
