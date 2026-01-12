<div align="center">

<img src="../assets/logo-header.svg" alt="zingのヘッダーロゴ">

Zigで作られた、ビジュアル重視のモダンディレクトリジャンパー。

[主要機能](#主要機能) • [使い方](#使い方) • [インストール](#インストール) • [カスタマイズ](#カスタマイズ) • [FAQ](#faq)

[English](README.md) | [日本語](README.ja.md)

[![Build Status](https://github.com/ydah/zing/workflows/CI/badge.svg)](https://github.com/ydah/zing/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/ydah/zing)](https://github.com/ydah/zing/releases)

</div>

zingは作業ディレクトリを学習し、曖昧な入力でも瞬時にジャンプできます。ファジーマッチング、frecencyスコアリング（頻度+最近性）、ライブプレビュー付きのTUIを備えています。

---

## 主要機能

### スマートジャンプ（ファジーマッチング）

断片的なパス入力から最適な候補を即時に選択します。

![スマートジャンプのデモ](assets/demo-jump.gif)

画像プレースホルダー: `assets/demo-jump.gif` にデモGIFを貼り付けてください。

### インタラクティブTUI（リスト/プレビュー/ツリー/統計）

`zi`で視覚的なセレクタを起動。検索・プレビュー・スコアバーをリアルタイム表示。

![TUIスクリーンショット](assets/tui-screenshot.png)

画像プレースホルダー: `assets/tui-screenshot.png` にスクリーンショットを貼り付けてください。

### Frecencyスコア

「よく使う×最近使った」を両立したランキング。

| ディレクトリ | スコア | 最終アクセス |
| --- | --- | --- |
| `~/projects/webapp` | 156.2 | 2分前 |
| `~/projects/api` | 89.4 | 1時間前 |
| `~/work/client` | 52.1 | 1日前 |

### サブディレクトリジャンプ

親ディレクトリから子へ段階的に移動できます。

```bash
z pro /src    # -> ~/projects/webapp/src
```

### ツリービューと統計ダッシュボード

階層構造や利用傾向をひと目で確認。

![ツリービュー](assets/tree-view.png)

画像プレースホルダー: `assets/tree-view.png` にツリービュー画像を貼り付けてください。

![統計ダッシュボード](assets/stats-dashboard.png)

画像プレースホルダー: `assets/stats-dashboard.png` に統計画面を貼り付けてください。

### テーマ

内蔵テーマ: `default`, `nord`, `dracula`, `gruvbox`

![テーマ比較](assets/themes-comparison.png)

画像プレースホルダー: `assets/themes-comparison.png` に比較画像を貼り付けてください。

---

## 使い方

### 基本コマンド

```bash
# 最適な候補へジャンプ
z foo

# 複数キーワードのAND検索
z foo bar

# インタラクティブモード
zi
zi foo
```

### サブディレクトリモード

```bash
z foo /        # サブディレクトリ選択
z foo /src     # 特定サブディレクトリへ
```

### 管理コマンド

```bash
zing add ~/new-project
zing remove ~/old-dir
zing list
zing list --format=json
zing stats
```

---

## インストール

### ソースからビルド（Zig 0.15.x）

```bash
git clone https://github.com/ydah/zing.git
cd zing
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/zing /usr/local/bin/
```

### シェル統合

```bash
# bash
source <(zing init bash)

# zsh
eval "$(zing init zsh)"

# fish
zing init fish | source
```

---

## 他ツールからの移行

```bash
# zoxide
zing import --from=zoxide

# z (rupa/z)
zing import --from=z ~/.z

# autojump
zing import --from=autojump
```

---

## 連携例

### fzf

```bash
z "$(zing list --format=text | fzf)"
```

### Neovim / Vim

```vim
command! -nargs=* Z :cd `zing query <args>`
```

### tmux

```bash
bind-key j display-popup -E "zi"
```

---

## カスタマイズ

### テーマ

```bash
zing config themes
zing config set tui.theme nord
```

### 設定ファイル

既定: `~/.config/zing/config.toml`（`ZING_CONFIG` で上書き）

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
patterns = [
  "^/tmp",
  ".*/node_modules/.*",
  ".*/\\.git/.*",
]
```

### 環境変数

| 変数 | 説明 | デフォルト |
| --- | --- | --- |
| `ZING_DATA_DIR` | DBの保存場所 | `~/.local/share/zing` |
| `ZING_CONFIG` | 設定ファイルのパス | `~/.config/zing/config.toml` |

---

## FAQ

### z/zi が見つからない

シェル統合が有効か確認してください。

```bash
grep zing ~/.bashrc  # または ~/.zshrc
```

### 候補に出てこないディレクトリがある

一度手動で追加してください。

```bash
zing add /path/to/dir
```

### スコアをリセットしたい

```bash
rm ~/.local/share/zing/zing.db
```

### TUIの表示が崩れる

TrueColor対応の端末が必要です。

```bash
echo $COLORTERM
```

---

## 比較

| 機能 | zing | zoxide | z | autojump |
| --- | --- | --- | --- | --- |
| 言語 | Zig | Rust | Shell | Python |
| インタラクティブTUI | ✅ | fzf依存 | ❌ | ❌ |
| Frecency（連続） | ✅ | ✅（離散） | ✅（離散） | ❌ |
| サブディレクトリ | ✅ | ✅ | ❌ | ❌ |
| ツリービュー | ✅ | ❌ | ❌ | ❌ |
| 統計ダッシュボード | ✅ | ❌ | ❌ | ❌ |
| テーマ | ✅ | ❌ | ❌ | ❌ |

---

## 開発

```bash
zig build
zig build -Doptimize=ReleaseFast
zig build test
```

コントリビュート歓迎です。手順は `CONTRIBUTING.md` を参照してください。

---

## ライセンス

MIT. `LICENSE` を参照。

## 謝辞

- [zoxide](https://github.com/ajeetdsouza/zoxide)
- [libvaxis](https://github.com/rockorager/libvaxis)
- [z](https://github.com/rupa/z)
