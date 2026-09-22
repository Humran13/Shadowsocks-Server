# Shadowsocks Server Manager

A polished, terminal-based manager for running your own [Shadowsocks](https://shadowsocks.org) server, built on the official [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) engine. One command to install, one command to manage.

## Install

On a fresh Ubuntu VPS (18.04, 20.04, 22.04, or 24.04, x86_64 or ARM64):

```bash
curl -fsSL https://raw.githubusercontent.com/Humran13/Shadowsocks-Server/main/install.sh | sudo bash
```

Then open the manager:

```bash
sudo shadowsocks
```

That's it — add a user, scan the QR code with your Shadowsocks client, and you're connected.

## Features

- Installs the official upstream `shadowsocks-rust` binaries (verified via checksum), no protocol reimplementation
- Clean terminal menu: add/list/show/enable/disable/delete users, diagnostics, logs, restart
- Auto-generated strong passwords, cipher-aware key lengths
- SIP002 `ss://` URI + terminal QR code for every user
- systemd service with auto-restart and hardened sandboxing
- UFW-aware firewall handling (TCP+UDP per port), never touches unrelated rules or SSH access
- Atomic, validated config writes with automatic rollback if a change breaks the service
- Non-interactive CLI subcommands for scripting/automation

## Supported systems

- Ubuntu 18.04, 20.04, 22.04, 24.04 (and newer LTS where compatible)
- x86_64 and ARM64 (aarch64)

## Adding a user

From the menu, choose **Add User**, or non-interactively:

```bash
sudo shadowsocks add alice 8388 chacha20-ietf-poly1305
```

You'll get the server details, a `ss://` connection URL, and a QR code to scan directly in a mainstream Shadowsocks client.

## Encryption methods

The manager only offers ciphers currently supported and recommended by shadowsocks-rust:

- `chacha20-ietf-poly1305` (default — best client compatibility)
- `aes-128-gcm`, `aes-256-gcm`
- `2022-blake3-aes-128-gcm`, `2022-blake3-aes-256-gcm`, `2022-blake3-chacha20-poly1305` (Shadowsocks 2022 AEAD — stronger, but check your client supports SS2022 before choosing these)

## TCP and UDP

Every user gets both TCP and UDP relay enabled on the same port, with matching firewall rules for both protocols. This has been verified with real end-to-end tests: an HTTPS request tunneled over TCP, and a DNS query tunneled over UDP via SOCKS5 UDP-ASSOCIATE.

## Command-line subcommands

```
shadowsocks status
shadowsocks add USERNAME [PORT] [METHOD]
shadowsocks list
shadowsocks show USERNAME
shadowsocks enable USERNAME
shadowsocks disable USERNAME
shadowsocks delete USERNAME
shadowsocks restart
shadowsocks logs [recent|live|errors]
shadowsocks diagnostics
```

## Diagnostics

`sudo shadowsocks diagnostics` (or menu option 7) checks the binary, config validity, systemd state, firewall, dependencies, disk space, and connectivity, reporting PASS/WARN/FAIL for each.

## Security notes

- Configuration and credentials live in `/etc/shadowsocks-server/`, root-owned, mode 600
- The manager never exposes any control API to the Internet
- Firewall changes only ever touch rules this project created — your SSH access is never modified
- Plain Shadowsocks is a proxy protocol, not a traffic-analysis-proof anonymity tool — don't market it as undetectable

## Uninstall

```bash
sudo shadowsocks uninstall
```
(or select **Uninstall** from the menu) — lets you choose whether to keep your configuration/backups or remove everything.

## Project structure

```
install.sh              one-line installer
bin/shadowsocks         manager CLI / TUI entrypoint
lib/common.sh           shared validation, config, secrets helpers
lib/uri.sh              SIP002 URI + QR generation
lib/firewall.sh         UFW abstraction
systemd/                systemd unit
tests/                  shellcheck, unit, and container integration tests
.github/workflows/      CI
```

## Acknowledgments

This project is a management layer around [shadowsocks/shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) — all credit for the Shadowsocks protocol implementation goes to that project and its maintainers. This repository does not modify or relicense that code.

## License

MIT — see [LICENSE](LICENSE).
