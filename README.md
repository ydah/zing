# zing

Modern directory jumper written in Zig.

## Install

```bash
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/zing /usr/local/bin/
```

## Shell integration

```bash
# bash
source <(zing init bash)

# zsh
eval "$(zing init zsh)"

# fish
zing init fish | source
```

## Usage

```bash
z <query>              # jump to best match
zi [query]             # interactive selector (TUI)

zing add <path>        # add path
zing remove <path>     # remove path
zing list              # list entries
zing list --format=json
zing stats             # show stats summary
zing import --from=z   # import from other tools
zing config            # show config
zing config set <k> <v>
```

Subdirectory jump:

```bash
z <query> /<subquery>
```

## Config

`~/.config/zing/config.toml` (or `$ZING_CONFIG`)

```toml
[general]
data_dir = "~/.local/share/zing"
cmd_alias = "z"
interactive_alias = "zi"

[scoring]
half_life = 604800
match_weight = 1.0
max_score = 1000.0
min_score = 0.01

[matching]
case_sensitivity = "smart"
search_type = "fuzzy"

[tui]
theme = "default"
show_preview = true
show_score_bar = true
highlight_matches = true

[exclude]
patterns = ["^/tmp", ".*/node_modules/.*"]
```

## Notes

- TUI is functional for list/preview/tree/stats, but rendering is still minimal.
- TUI subdirectory mode: press `/` to enter, `Backspace` on empty to exit.
- TUI preview paging: `Alt+Left/Right` to scroll preview grid.
- zoxide binary `db.zo` import uses the `zoxide` CLI if available; text-format exports also work.
