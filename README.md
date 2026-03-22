# zit
zig with a typo, somehow faster than `zig run` (**1.84× faster**).

## Install

```sh
make
make install   # installs to ~/bin
```

## Usage

```sh
# run a zig file
zit ./path/to/source.zig

# or run it directly via shebang
chmod +x ./path/to/source.zig
./path/to/source.zig
```

```zig
#!/usr/bin/env zit
const std = @import("std");
pub fn main() void { std.debug.print("hello\n", .{}); }
```

```sh
# project example
zit examples/hello.zig
chmod +x examples/hello.zig
./examples/hello.zig
```

## Runtime comparison

| scenario | zig run (`examples/hello.zig`) | zit (`examples/hello.zig`) |
|---|---:|---:|
| cold start | `3616 ms` | `1968 ms` (`--recompile`) |
| warm start | `24 ms` | `2 ms` |

## Bench env (container)

- Linux container, x86_64
- Zig `0.15.2`
- workload: `examples/hello.zig`
