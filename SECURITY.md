# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub Security Advisories on this repository ("Security" tab → "Report a vulnerability") rather than opening a public issue. Include reproduction steps and impact where possible.

## Scope

This repository covers the installer, manager CLI, systemd unit, and firewall/config handling around the upstream `shadowsocks-rust` engine. Vulnerabilities in the Shadowsocks protocol implementation itself should be reported upstream at [shadowsocks/shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust/security).

## Design notes relevant to security review

- All configuration/credentials live under `/etc/shadowsocks-server/`, root-owned, mode 600
- No manager API is ever exposed over the network
- Config writes are atomic (temp file + validate + rename) with automatic rollback on failed apply
- All user-supplied input (username, port, cipher, date) is validated against strict allowlists before being used in any file path, JSON value, or shell command
- Firewall rule changes only ever touch rules tagged as owned by this project
- Downloaded release binaries are checksum-verified against upstream-published SHA-256 sums when available

## Known limitations

- Plain Shadowsocks traffic can potentially be fingerprinted by sophisticated deep packet inspection; this project does not claim otherwise
- Per-user traffic quotas rely on shadowsocks-rust's own accounting; treat them as best-effort, not hard guarantees
