# timez

A simple Windows command-line utility to measure process running time (total elapsed, kernel, and user), as well as peak working set and number of page faults.

## Usage

```console
timez command [arguments...]
```

## Build

You'll probably need a recent nightly build of the Zig compiler to build this project.
Consider using [zigup](https://github.com/marler8997/zigup) (`zigup master`).

```console
zig build -Doptimize=ReleaseFast
```

The artifacts will be placed in `zig-out/bin/`.

## Known issues

- Kernel/user time is wrong for multi-threaded processes.

## To-do

- [ ] See if it's possible to get number of context switches without requiring admin rights.
- [ ] Investigate why sometimes kernel/user times are zero for short-lived processes.

## License

[0BSD](LICENSE.txt)
