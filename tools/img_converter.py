#!/usr/bin/env python3
"""
VBXE Image Converter Server

Converts web images to raw VBXE format (8bpp indexed color).
Atari browser calls: http://server:8080/img?url=IMAGE_URL&w=80&h=60

Response format:
  2 bytes: width (16-bit LE)
  1 byte:  height
  768 bytes: palette (256 x R,G,B)
  w*h bytes: pixel data (1 byte per pixel, palette index)

Requires: pip install Pillow flask

Usage: python img_converter.py [port]
"""

from flask import Flask, request, Response
from PIL import Image
import urllib.request
import struct
import io
import sys

app = Flask(__name__)
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

@app.route('/img')
def convert():
    url = request.args.get('url', '')
    w = min(int(request.args.get('w', 80)), 320)
    h = min(int(request.args.get('h', 60)), 192)

    if not url:
        return 'Missing url parameter', 400

    try:
        # Download image
        req = urllib.request.Request(url, headers={
            'User-Agent': 'VBXE-ImageProxy/1.0'
        })
        with urllib.request.urlopen(req, timeout=10) as resp:
            img_data = resp.read()

        # Open and convert
        img = Image.open(io.BytesIO(img_data))
        img = img.convert('RGB')
        img = img.resize((w, h), Image.LANCZOS)

        # Quantize to 256 colors
        img_q = img.quantize(colors=248, method=Image.MEDIANCUT)
        # Reserve first 8 palette entries for text colors

        # Build output
        out = bytearray()

        # Header: width (16-bit LE), height (8-bit)
        out += struct.pack('<HB', w, h)

        # Palette: 256 x RGB
        pal = img_q.getpalette()  # 768 bytes (256*3)
        # Shift palette: entries 0-7 = text colors, 8-255 = image colors
        # Write 8 dummy entries for text colors (browser will skip these)
        for i in range(8 * 3):
            out.append(0)
        # Write image palette at indices 8-255
        for i in range(248 * 3):
            out.append(pal[i] >> 1)  # VBXE uses 7-bit RGB

        # Pixel data: offset by 8 to avoid text color indices
        pixels = img_q.tobytes()
        for b in pixels:
            out.append(b + 8)  # shift palette index by 8

        return Response(bytes(out), mimetype='application/octet-stream')

    except Exception as e:
        return f'Error: {e}', 500

@app.route('/')
def index():
    return '''<h1>VBXE Image Converter</h1>
    <p>Usage: /img?url=IMAGE_URL&w=80&h=60</p>
    <p>Returns raw VBXE 8bpp image data (palette + pixels)</p>'''

if __name__ == '__main__':
    print(f'VBXE Image Converter on port {PORT}')
    print(f'Test: http://localhost:{PORT}/img?url=https://picsum.photos/80/60&w=80&h=60')
    app.run(host='0.0.0.0', port=PORT)
