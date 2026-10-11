# Hack Compiler

_Bundle a Hack application into a single file for simple CLIs or servers_

## When not to use

This is not meant to replace your production releases. You should keep doing
releases in the way you are used to. This compiler is meant to package up
applications into a single file to distribute to others. Think of it as a step
above giving someone an entire checkout of your repository, but below a docker
image. It fills the middleground for developer tooling where hhvm is already
installed.

## Usage

```sh
# A cli application
vendor/bin/hack-compiler.sh --mode cli --root src --root bin/main.hack \
  --typecheck > application.sh
chmod +x application.sh
./application.sh --help
./application.sh --hhvm-args -dhhvm.jit=0 -- --help

# A server
vendor/bin/hack-compiler.sh --mode server --root src --root bin/server.hack \
  --typecheck > server.sh
chmod +x server.sh
./server.sh -p 10641
./server.sh -d -p 10641 # Run in the background instead
```

## Advanced usage

```SH
# Compile a CLI to a resource and invoke it directly with HHVM
vendor/bin/hack-compiler.sh --mode resource --root src --root bin/main.hack \
  --typecheck > application.resource
hhvm -dhhvm.jit=0 application.resource --help

# Serve a separate resource directly
vendor/bin/hack-compiler.sh --mode resource --root src --root bin/server.hack \
  --typecheck > server.resource
vendor/bin/hack-compiler-serve-resource.sh -b ./server.resource -d -p 10641
```

## CLI

```CLI
hack-compiler.sh --mode MODE --root PATH [--root PATH...] [--exclude PREFIX...] [--typecheck]
hack-compiler-serve-resource.sh -b PATH [-p PORT] [-g] [-d]

--mode MODE       Required: resource, cli, server, or server-obsolete.
--root PATH       Required. Select a file or recursively collect .hack files
                  from a directory. May be repeated; overlaps are deduplicated.
--exclude PREFIX  Skip paths starting with this prefix. May be repeated.
--typecheck       Check the combined source with hh_server before emitting it.
--help            Show usage.

Paths may be relative or absolute. Output is written to stdout.

resource          Emit plain Hack source.
cli               Embed source in a shell launcher that invokes its entrypoint.
server            Embed source in a server launcher. Supports -d and -p PORT.
server-obsolete   Preserve the legacy Linters Server launcher. Pass -e to use
                  embedded source; -b PATH selects an external resource.

CLI launchers:    --hhvm-args starts HHVM options; -- resumes script arguments.
                  Without --hhvm-args, all arguments go to the script.
```

Embedded server modes rewrite `__FILE__` and `__DIR__` expressions to refer to
the canonical launcher path and its directory (symlinks are resolved). The
replacement reads the launcher path at runtime, including in contexts that
require constants. Use `--typecheck` to catch illegal constant expressions and
incompatible effects before emitting the launcher. Without it, HHVM rejects
illegal constant expressions when the resource is loaded at runtime.

The rewritten resource requires the environment variable supplied by the
launcher. The rewrite replaces matching name tokens even in declaration, type
and member positions; unusual uses of these names can fail to parse or run.
Strings, comments and literal XHP content stay unchanged.
