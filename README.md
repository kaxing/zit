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

## Example

```sh
zit examples/hello.zig
```

## Runtime comparison

| scenario | zig run (`examples/hello.zig`) | zit (`examples/hello.zig`) |
|---|---:|---:|
| cold start | `3616 ms` | `1968 ms` (`--force`) |
| warm start | `24 ms` | `2 ms` |

## Bench env (container)

- Linux container, x86_64
- Zig `0.15.2`
- workload: `examples/hello.zig`
