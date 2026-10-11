#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .var
hhvm -dhhvm.autoload.enabled=true -dhhvm.autoload.db.path=.var/facts.db \
  bin/hack-compiler.hack --mode cli --root src --root bin/hack-compiler.hack \
  > bin/hack-compiler.sh
chmod +x bin/hack-compiler.sh
