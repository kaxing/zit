# zit
zig with a typo, somehow faster than `zig run` (**1.84× faster**).

## Install

```sh
make
make install   # installs to ~/bin
```

## Usage

```sh
zit ./path/to/source.zig
```

## Runtime comparison

| scenario | command | median |
|---|---|---:|
| fresh recompile | `zig run examples/hello.zig` | `3616 ms` |
| fresh recompile | `zit --force examples/hello.zig` | `1968 ms` |
| cached run | `zig run examples/hello.zig` | `24 ms` |
| cached run | `zit examples/hello.zig` | `2 ms` |

## Bench env (container)

- Linux container, x86_64
- Zig `0.15.2`
- workload: `examples/hello.zig`
