# zit
zig with a typo, somehow faster than `zig run` (**1.64× faster**).

## Install

```sh
make
make install   # installs to ~/bin
```

## Usage

```sh
# run
zit ./path/to/source.zig

# force rebuild
zit --recompile ./path/to/source.zig

# clean all caches
zit clean-caches

# toggle shebang in-place
zit toggle-shebang ./path/to/source.zig

# run directly via shebang
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

## Comparison

Bench env: Linux container (x86_64), Zig `0.15.2`, 3 rounds, workload: `hello.zig` source (shebang-stripped copy).

| scenario | zig run | zit |
|---|---:|---:|
| cold start | `2331 ms` | `1419 ms` (`--recompile`) |
| warm start | `16 ms` | `1 ms` |
