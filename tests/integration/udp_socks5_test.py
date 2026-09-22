#!/usr/bin/env python3
"""Manual SOCKS5 UDP-ASSOCIATE test: sends a real DNS query for example.com
to 8.8.8.8:53 through the sslocal SOCKS5 UDP relay (which tunnels it over
the Shadowsocks UDP port), to verify UDP actually proxies traffic end-to-end.
"""
import socket
import struct
import sys

SOCKS_HOST, SOCKS_PORT = "127.0.0.1", 1080
DNS_HOST, DNS_PORT = "8.8.8.8", 53

# 1. TCP control connection: SOCKS5 handshake + UDP ASSOCIATE
tcp = socket.create_connection((SOCKS_HOST, SOCKS_PORT), timeout=8)
tcp.sendall(b"\x05\x01\x00")  # ver=5, 1 method, no-auth
resp = tcp.recv(2)
assert resp == b"\x05\x00", f"unexpected greeting response: {resp!r}"

# UDP ASSOCIATE request; client address 0.0.0.0:0 (let server decide)
tcp.sendall(b"\x05\x03\x00\x01" + socket.inet_aton("0.0.0.0") + struct.pack("!H", 0))
resp = tcp.recv(10)
assert resp[1] == 0, f"UDP ASSOCIATE failed, rep={resp[1]}"
bnd_addr = socket.inet_ntoa(resp[4:8])
bnd_port = struct.unpack("!H", resp[8:10])[0]
if bnd_addr == "0.0.0.0":
    bnd_addr = SOCKS_HOST

# 2. Send a UDP DNS query wrapped in a SOCKS5 UDP header to the relay
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.settimeout(8)

dns_query = bytes.fromhex(
    "aaaa0100000100000000000007"
    "6578616d706c6503636f6d0000010001"
)  # standard A-record query for example.com

socks_header = b"\x00\x00\x00\x01" + socket.inet_aton(DNS_HOST) + struct.pack("!H", DNS_PORT)
udp.sendto(socks_header + dns_query, (bnd_addr, bnd_port))

try:
    data, _ = udp.recvfrom(4096)
except socket.timeout:
    print("UDP_TEST_RESULT=FAIL (timeout, no UDP response through relay)")
    sys.exit(1)

# Response also carries a SOCKS5 UDP header; strip it and confirm it's a DNS reply
if len(data) > 10 and data[4:8] == socket.inet_aton(DNS_HOST):
    dns_reply = data[10:]
    if dns_reply[:2] == dns_query[:2] and (dns_reply[2] & 0x80):
        print(f"UDP_TEST_RESULT=PASS ({len(dns_reply)} byte DNS reply received through Shadowsocks UDP relay)")
        sys.exit(0)

print("UDP_TEST_RESULT=FAIL (response did not look like a valid DNS reply)")
sys.exit(1)
