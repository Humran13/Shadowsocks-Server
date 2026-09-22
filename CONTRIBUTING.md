# Contributing

Contributions are welcome. A few ground rules to keep this project reliable for people installing it on real servers:

## Before submitting a change

- Run `shellcheck -x` against any modified `.sh` files (or `bin/shadowsocks`) and fix warnings/errors
- If you change `lib/` or `bin/shadowsocks` behavior, test it in a real container (see `tests/integration/`), not just by reading the code
- Never introduce `eval` on user-controlled input, unquoted variable expansion, or unvalidated shell interpolation
- Keep the manager working with both `enabled` and `disabled` users, zero users, and a freshly-uninstalled state — these are exercised in CI

## Scope

- The Shadowsocks protocol itself is not implemented here — this project installs and manages the official `shadowsocks-rust` binaries. Protocol-level changes belong upstream.
- Firewall and systemd changes must remain scoped to resources this project owns; never touch unrelated rules, unrelated services, or SSH access.

## Pull requests

- Keep PRs focused on one change
- Describe what was tested and how (container OS/version, commands run)
- CI (shellcheck + unit tests + container integration matrix) must pass
