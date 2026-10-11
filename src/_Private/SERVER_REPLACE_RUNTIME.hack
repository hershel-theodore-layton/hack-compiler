/** hack-compiler is MIT licensed, see /LICENSE. */
namespace HTL\HackCompiler\_Private;

const string SERVER_REPLACE_RUNTIME = <<<'SH'
nonce=$(basename "$work_dir")
pid_namespace=$(readlink /proc/self/ns/pid)

# 0: compatible server, 1: no listener, 2: failed or unrecognized handshake.
handshake() {
  handshake_status=0
  handshake_reply=$(curl --noproxy '*' --fail --silent --max-time 1 \
    "http://127.0.0.1:$port/?__hack_compiler_handshake=$nonce") || handshake_status=$?
  if [ "$handshake_status" -eq 7 ]; then return 1; fi
  if [ "$handshake_status" -ne 0 ]; then return 2; fi
  case "$handshake_reply" in
    "hack-compiler/1:$nonce:$pid_namespace:"*) ;;
    *) return 2 ;;
  esac
  handshake_reply=${handshake_reply#"hack-compiler/1:$nonce:$pid_namespace:"}
  handshake_instance=${handshake_reply%:*}
  handshake_pid=${handshake_reply##*:}
  case "$handshake_instance" in ''|*[!a-zA-Z0-9.]*) return 2 ;; esac
  case "$handshake_pid" in ''|*[!0-9]*) return 2 ;; esac
  test "$handshake_pid" -gt 1 || return 2
}

if handshake; then
  previous_pid=$handshake_pid
  previous_instance=$handshake_instance
  echo "Replacing server on port $port."
  if ! kill -INT "$previous_pid"; then
    echo "Could not stop the previous server on port $port." >&2
    exit 1
  fi
  attempts=0
  while :; do
    if handshake; then
      if [ "$handshake_pid" != "$previous_pid" ] ||
         [ "$handshake_instance" != "$previous_instance" ]; then
        echo "Port $port changed owners while replacing the server." >&2
        exit 1
      fi
    elif [ "$?" -eq 1 ]; then
      break
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 50 ]; then
      echo "Previous server did not release port $port." >&2
      exit 1
    fi
    sleep 0.1
  done
elif [ "$?" -ne 1 ]; then
  echo "Port $port did not complete the hack-compiler handshake; leaving it running." >&2
  exit 1
fi

export HACK_COMPILER_SERVER_INSTANCE=$nonce
SH;
