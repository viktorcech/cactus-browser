#!/usr/bin/env python3
"""
Serial HTTP Proxy for VBXE Browser (Atari 850 Interface)

Mode 1 (default): Listen on port, wait for Altirra to connect
Mode 2 (-c): Connect to Altirra's listening port

Protocol:
  Browser sends: GET <url>\r\n
  Proxy fetches URL, sends back HTML body + EOT (0x04)

Usage:
  python serial_proxy.py [port]           - listen mode (default port 9001)
  python serial_proxy.py -c [host] [port] - connect mode
"""

import socket
import sys
import urllib.request
import time

EOT = bytes([0x04])

def fetch_url(url):
    try:
        if not url.startswith('http'):
            url = 'http://' + url
        req = urllib.request.Request(url, headers={
            'User-Agent': 'VBXE-Browser/1.0 (Atari XE/XL)'
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read()
    except Exception as e:
        return f'<html><body><h1>Error</h1><p>{e}</p></body></html>'.encode()

def handle(sock):
    buf = b''
    try:
        while True:
            data = sock.recv(1024)
            if not data:
                break
            buf += data
            # Show raw bytes for debugging
            print(f'  raw: {data.hex()} = {repr(data)}')

            while b'\n' in buf:
                line, buf = buf.split(b'\n', 1)
                line = line.strip()
                if not line:
                    continue
                if line.upper().startswith(b'GET '):
                    url = line[4:].decode('ascii', errors='ignore').strip()
                    print(f'[>] GET {url}')
                    html = fetch_url(url)
                    sock.sendall(html + EOT)
                    print(f'[<] Sent {len(html)} bytes + EOT')
                else:
                    print(f'[?] {line}')
    except Exception as e:
        print(f'Error: {e}')

def listen_mode(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', port))
    srv.listen(1)
    print(f'Listening on port {port} - waiting for Altirra...')

    while True:
        conn, addr = srv.accept()
        print(f'[+] Connected: {addr}')
        handle(conn)
        conn.close()
        print(f'[-] Disconnected, waiting again...')

def connect_mode(host, port):
    while True:
        print(f'Connecting to {host}:{port}...')
        try:
            s = socket.socket()
            s.connect((host, port))
            print('Connected!')
            handle(s)
            s.close()
        except Exception as e:
            print(f'  Error: {e}')
        print('Reconnecting in 2s...')
        time.sleep(2)

if __name__ == '__main__':
    print('=== VBXE Browser Serial Proxy ===')
    if '-c' in sys.argv:
        sys.argv.remove('-c')
        host = sys.argv[1] if len(sys.argv) > 1 else 'localhost'
        port = int(sys.argv[2]) if len(sys.argv) > 2 else 9000
        connect_mode(host, port)
    else:
        port = int(sys.argv[1]) if len(sys.argv) > 1 else 9001
        listen_mode(port)
