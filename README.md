# Helix Setup & Installer

Personal [Helix](https://helix-editor.com/) editor configuration and portable POSIX installer for Linux and macOS (`x86_64` / `aarch64`).

## Quick Install (One-Liner)

Using `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/DenHafiz69/helix/main/install.sh | sh
```

Using `wget`:

```sh
wget -qO- https://raw.githubusercontent.com/DenHafiz69/helix/main/install.sh | sh
```

### Passing Flags to the One-Liner

Use `sh -s --` to forward options to the installer:

```sh
# Install only config.toml and languages.toml (skip binary)
curl -fsSL https://raw.githubusercontent.com/DenHafiz69/helix/main/install.sh | sh -s -- --config-only

# Pin a specific Helix version
curl -fsSL https://raw.githubusercontent.com/DenHafiz69/helix/main/install.sh | sh -s -- --version 25.01.1
```

## Local Install

```sh
git clone https://github.com/DenHafiz69/helix.git
cd helix
./install.sh
```

## Options & Environment Variables

Run `./install.sh --help` to see all options:

| Flag | Env Variable | Default | Description |
| :--- | :--- | :--- | :--- |
| `-v, --version VERSION` | `HELIX_VERSION` | Latest release | Pin a specific Helix version |
| `--install-dir DIR` | `INSTALL_DIR` | `~/.local/bin` | Destination for the `hx` binary |
| `--config-dir DIR` | `HELIX_CONFIG_DIR` | `~/.config/helix` | Destination for runtime and `.toml` configs |
| `--config-only` | — | — | Only install/update `config.toml` and `languages.toml` |
| `--no-config` | — | — | Only install `hx` binary and runtime |
| `--no-backup` | — | — | Overwrite existing configs without `.bak` backups |
| — | `REPO_SLUG` | `DenHafiz69/helix` | GitHub repository for remote config downloads |
| — | `BRANCH` | `main` | Git branch for remote config downloads |
| — | `NO_COLOR` | — | Set to disable colored output |

> **Note:** Existing `config.toml` or `languages.toml` files that differ from the incoming ones are automatically backed up with a `.bak.<timestamp>` suffix unless `--no-backup` is passed.

## Requirements

- `curl` or `wget`
- `tar` and `xz` (for extracting `.tar.xz` release archives)
- Ensure `~/.local/bin` (or your custom `--install-dir`) is in your `PATH`:

```sh
export PATH="$PATH:$HOME/.local/bin"
```

## Included Configuration

- `config.toml`: `catppuccin_frappe` theme, relative line numbers, `auto-format`, `color-modes`, `bufferline = "multiple"`, cursor shapes, and `esc` selection collapse.
- `languages.toml`: Language settings for Markdown, plain text, Python (`ruff`), Go, and HTML (`vscode-html-language-server`, `prettier`).
