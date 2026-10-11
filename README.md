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

--mode MODE           Required: resource, cli, server, or server-obsolete.
--root PATH           Required. Select a file or recursively collect .hack files
                      from a directory. May be repeated; overlaps are deduplicated.
--exclude PREFIX      Skip paths starting with this prefix. May be repeated.
--typecheck           Check the combined source with hh_server before emitting it.
--enable-self-update  Allow another server to replace a running one.
--help                Show usage.

Paths may be relative or absolute. Output is written to stdout.

resource              Emit plain Hack source.
cli                   Embed source in a shell launcher that invokes its entrypoint.
server                Embed source in a server launcher. Supports -d and -p PORT.
server-obsolete       Preserve the legacy Linters Server launcher. Pass -e to use
                      embedded source; -b PATH selects an external resource.

CLI launchers:        --hhvm-args starts HHVM options; -- resumes script arguments.
                      Without --hhvm-args, all arguments go to the script.
```

## Mangling

When compiling in server mode, the hack-compiler does a best-effort to make
`__FILE__` and `__DIR__` refer to your server script. This transformation might
result in a parse error at start-up. `--typecheck` will inform you if your code
has been mangled wrong.

## Servers that self update

If you compiled your server with `--enable-self-update`, a small shim is
injected before your application code. It identifies itself on requests matching
`/?__hack_compiler_handshake`. If you then start a second server on the same
port, the launcher will kill the process of the old server before taking its
place.
