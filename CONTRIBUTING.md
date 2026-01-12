# Contributing to zing

Thanks for your interest in contributing.

## Development setup

- Zig 0.15.x
- libvaxis and sqlite-zig are fetched by `zig build`

Build and test:

```bash
zig build
zig build -Doptimize=ReleaseFast
zig build test
```

## Code style

- Follow Zig's standard style.
- Function names: camelCase
- Type names: PascalCase
- Constants: SCREAMING_SNAKE_CASE
- Prefer `try` for error propagation.

## Submitting changes

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-change`
3. Commit with a clear message
4. Open a pull request

## Reporting bugs

Please include:
- OS and shell
- zig version (`zig version`)
- steps to reproduce
- expected vs actual behavior

## Requesting features

Describe the problem, proposed solution, and any alternatives.
