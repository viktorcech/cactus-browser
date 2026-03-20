#!/usr/bin/env python3
"""
Named Pipe HTTP Proxy for VBXE Browser
Altirra creates pipe, this script connects as client.

In Altirra: 850 > Serial port 1 > Named pipe serial adapter
  pipe name: \\.\pipe\atari850

Usage: python pipe_proxy.py
"""
import time
import urllib.request
import sys
import os
import msvcrt

EOT = bytes([0x04])
PIPE_NAME = r'\\.\pipe\atari850'

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

def main():
    print('=== VBXE Browser Named Pipe Proxy ===')
    print(f'Pipe: {PIPE_NAME}')
    print()

    while True:
        print(f'Waiting for pipe {PIPE_NAME}...')

        # Wait for Altirra to create the pipe
        while True:
            try:
                # Open pipe as file (Altirra creates it, we connect)
                pipe = open(PIPE_NAME, 'r+b', buffering=0)
                print('CONNECTED!')
                break
            except FileNotFoundError:
                time.sleep(1)
            except PermissionError:
                print('  Pipe busy, retrying...')
                time.sleep(1)
            except Exception as e:
                print(f'  {e}')
                time.sleep(2)

        buf = b''
        try:
            while True:
                # Read available data
                data = pipe.read(1)
                if not data:
                    break
                # Try to read more
                try:
                    while True:
                        more = pipe.read(1)
                        if not more:
                            break
                        data += more
                        if len(data) >= 256:
                            break
                except:
                    pass

                buf += data
                print(f'  recv ({len(data)}b): {repr(data)}')

                while b'\n' in buf:
                    line, buf = buf.split(b'\n', 1)
                    line = line.strip()
                    if not line:
                        continue

                    if line.upper().startswith(b'GET '):
                        url = line[4:].decode('ascii', errors='ignore').strip()
                        print(f'[>] GET {url}')
                        html = fetch_url(url)
                        pipe.write(html + EOT)
                        pipe.flush()
                        print(f'[<] Sent {len(html)} bytes + EOT')
                    else:
                        print(f'[?] {line}')

        except Exception as e:
            print(f'Error: {e}')

        try:
            pipe.close()
        except:
            pass
        print('Disconnected. Retrying...\n')
        time.sleep(2)

if __name__ == '__main__':
    main()
