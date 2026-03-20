/**
 * Serial HTTP Proxy for VBXE Browser (Atari 850 Interface)
 *
 * Listens on TCP port, accepts connections from Altirra modem.
 * Protocol:
 *   Browser sends: GET <url>\r\n
 *   Proxy fetches URL, sends back HTML body + EOT (0x04)
 *
 * Usage: node serial_proxy.js [port]
 * Default port: 9000
 *
 * In Altirra: System > Devices > 850 > Modem
 *   Set modem to connect to: localhost:9000
 */

const net = require('net');
const http = require('http');
const https = require('https');
const { URL } = require('url');

const EOT = Buffer.from([0x04]);
const PORT = parseInt(process.argv[2]) || 9000;

function fetchUrl(urlStr) {
    return new Promise((resolve) => {
        try {
            if (!urlStr.startsWith('http')) urlStr = 'http://' + urlStr;
            const parsed = new URL(urlStr);
            const client = parsed.protocol === 'https:' ? https : http;

            const req = client.get(urlStr, {
                headers: { 'User-Agent': 'VBXE-Browser/1.0 (Atari XE/XL)' },
                timeout: 15000
            }, (res) => {
                // Follow redirects
                if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                    console.log(`[~] Redirect -> ${res.headers.location}`);
                    fetchUrl(res.headers.location).then(resolve);
                    return;
                }

                const chunks = [];
                res.on('data', (chunk) => chunks.push(chunk));
                res.on('end', () => resolve(Buffer.concat(chunks)));
                res.on('error', (e) => {
                    resolve(Buffer.from(`<html><body><h1>Error</h1><p>${e.message}</p></body></html>`));
                });
            });

            req.on('error', (e) => {
                resolve(Buffer.from(`<html><body><h1>Error</h1><p>${e.message}</p></body></html>`));
            });

            req.on('timeout', () => {
                req.destroy();
                resolve(Buffer.from('<html><body><h1>Timeout</h1></body></html>'));
            });
        } catch (e) {
            resolve(Buffer.from(`<html><body><h1>Error</h1><p>${e.message}</p></body></html>`));
        }
    });
}

const server = net.createServer((socket) => {
    const addr = `${socket.remoteAddress}:${socket.remotePort}`;
    console.log(`[+] Connection from ${addr}`);

    let buf = '';

    socket.on('data', (data) => {
        buf += data.toString('ascii');

        let nlPos;
        while ((nlPos = buf.indexOf('\n')) !== -1) {
            const line = buf.substring(0, nlPos).trim();
            buf = buf.substring(nlPos + 1);

            if (!line) continue;

            if (line.toUpperCase().startsWith('GET ')) {
                const url = line.substring(4).trim();
                console.log(`[>] GET ${url}`);

                fetchUrl(url).then((html) => {
                    if (!socket.destroyed) {
                        socket.write(Buffer.concat([html, EOT]));
                        console.log(`[<] Sent ${html.length} bytes + EOT`);
                    }
                });
            } else {
                console.log(`[?] Unknown: ${line}`);
            }
        }
    });

    socket.on('close', () => console.log(`[-] Closed: ${addr}`));
    socket.on('error', (e) => console.log(`[!] Error: ${e.message}`));
});

server.listen(PORT, () => {
    console.log('=== VBXE Browser Serial Proxy ===');
    console.log(`Listening on port ${PORT}`);
    console.log(`In Altirra: modem connect to localhost:${PORT}`);
    console.log();
});
