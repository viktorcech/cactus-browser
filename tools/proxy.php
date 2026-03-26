<?php
/**
 * HTML cleaning proxy for VBXE Browser (Atari 8-bit)
 * Strips scripts, styles, SVG, empty tags, and unnecessary attributes.
 * Converts relative URLs to absolute.
 *
 * Usage: https://turiecfoto.sk/proxy.php?url=ta3.com
 * Atari: N:https://turiecfoto.sk/proxy.php?url=ta3.com
 */

// Get URL parameter
$url = $_GET['url'] ?? '';
if (!$url) {
    header('Content-Type: text/html; charset=utf-8');
    echo '<html><body><h1>VBXE Browser Proxy</h1>';
    echo '<p>Usage: ?url=example.com</p></body></html>';
    exit;
}

// Add http:// if missing
if (!preg_match('#^https?://#i', $url)) {
    $url = 'http://' . $url;
}

// Cache: serve processed result from disk if fresh (10 min TTL)
$cacheDir = __DIR__ . '/proxy_cache';
if (!is_dir($cacheDir)) @mkdir($cacheDir, 0755);
$cacheFile = $cacheDir . '/' . md5($url) . '.html';

if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 600) {
    while (ob_get_level()) ob_end_clean();
    header('Content-Type: text/html; charset=utf-8');
    header('Content-Length: ' . filesize($cacheFile));
    header('Connection: close');
    readfile($cacheFile);
    exit;
}

// Parse base URL for relative link resolution
$parsed = parse_url($url);
$base_scheme = ($parsed['scheme'] ?? 'http');
$base_host = ($parsed['host'] ?? '');
$base_origin = $base_scheme . '://' . $base_host;
$base_path = $parsed['path'] ?? '/';
$base_dir = substr($base_path, 0, strrpos($base_path, '/') + 1) ?: '/';

// Fetch the page using curl (gzip support, better error handling)
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_MAXREDIRS, 5);
curl_setopt($ch, CURLOPT_TIMEOUT, 15);
curl_setopt($ch, CURLOPT_ENCODING, '');  // accept gzip/deflate/br, auto-decompress
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'User-Agent: Mozilla/5.0 (compatible; VBXEBrowser/1.0)',
    'Accept: text/html,*/*',
    'Accept-Language: sk,en;q=0.5',
]);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);

$html = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_error($ch);
$final_url = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
$content_type = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
curl_close($ch);

if ($html === false || $code >= 400) {
    header('Content-Type: text/html; charset=utf-8');
    echo '<html><body><h1>Error</h1><p>Cannot fetch: ' . htmlspecialchars($url)
       . ' (HTTP ' . $code . ' ' . $err . ')</p></body></html>';
    exit;
}

// Update base from final URL after redirects
if ($final_url && $final_url !== $url) {
    $rp = parse_url($final_url);
    if (isset($rp['host'])) {
        $base_scheme = $rp['scheme'] ?? $base_scheme;
        $base_host = $rp['host'];
        $base_origin = $base_scheme . '://' . $base_host;
        $base_dir = substr($rp['path'] ?? '/', 0, strrpos($rp['path'] ?? '/', '/') + 1) ?: '/';
    }
}

// Detect encoding: HTTP header first (fast), then HTML meta fallback
$charset = 'utf-8';
if ($content_type && preg_match('/charset=([^\s;]+)/i', $content_type, $m)) {
    $charset = strtolower(trim($m[1]));
} elseif (preg_match('/charset=(["\']?)([^"\'\s;>]+)/i', $html, $m)) {
    $charset = strtolower(trim($m[2]));
}
if ($charset !== 'utf-8') {
    // Normalize encoding names for mb_convert_encoding (PHP 8.x strict)
    $enc_map = [
        'windows-1250' => 'CP1250', 'windows-1251' => 'CP1251',
        'windows-1252' => 'CP1252', 'windows-1253' => 'CP1253',
        'windows-1254' => 'CP1254', 'windows-1256' => 'CP1256',
        'iso-8859-2' => 'ISO-8859-2', 'iso-8859-1' => 'ISO-8859-1',
        'iso-8859-15' => 'ISO-8859-15',
    ];
    $enc = $enc_map[$charset] ?? $charset;
    try {
        $html = mb_convert_encoding($html, 'UTF-8', $enc) ?: $html;
    } catch (\ValueError $e) {
        // Unknown encoding — serve as-is (best effort)
    }
}

// Extract <title> before stripping <head> (browser displays it)
$title = '';
if (preg_match('/<title[^>]*>(.*?)<\/title>/si', $html, $tm)) {
    $title = '<title>' . $tm[1] . '</title>';
}

// Strip entire <head> block (meta, link, inline styles — 5-15KB saved)
$html = preg_replace('/<head[\s>].*?<\/head>/si', '<head>' . $title . '</head>', $html);

// Strip junk (single pass with array of patterns)
$html = preg_replace([
    '/<!--.*?-->/s',                          // comments
    '/<(script|style|svg|button|iframe|object|form|select|textarea|picture)[\s>].*?<\/\1>/si',
    '/<(input|source|link|meta|script)[^>]*\/?>/i',  // void tags useless on Atari
    '/<(noscript|label)[^>]*>/i',             // unwrap (open)
    '/<\/(noscript|label)>/i',                // unwrap (close)
    '/\s+(?!href|src|alt)[\w-]+=(?:"[^"]*"|\'[^\']*\'|\S+)/i',  // strip attrs with values (keep href, src, alt)
    '/\s+(?:itemscope|itemtype|hidden|async|defer|novalidate|disabled|checked|readonly|autofocus|autoplay|controls|loop|muted|playsinline)\b/i',  // strip boolean attrs
], '', $html);

// Remove empty tags (2 passes to catch nested empties)
$empty = '/<(span|div|a|b|i|em|strong|u|font|small|big|li|ul|ol|p|section|nav|article|aside|header|footer|main)[^>]*>\s*<\/\1>/si';
$html = preg_replace($empty, '', $html);
$html = preg_replace($empty, '', $html);

// Convert relative URLs to absolute in href and src attributes
$html = preg_replace_callback(
    '/(href|src)=(["\'])([^"\']+)\2/i',
    function ($m) use ($base_scheme, $base_origin, $base_dir) {
        $attr = $m[1];
        $quote = $m[2];
        $val = $m[3];
        // Skip already absolute, javascript:, mailto:, #anchors, data:
        if (preg_match('/^(https?:\/\/|javascript:|mailto:|data:|#)/i', $val)) {
            return $attr . '=' . $quote . $val . $quote;
        }
        if (substr($val, 0, 2) === '//') {
            // Protocol-relative (//cdn.example.com/...)
            $abs = $base_scheme . ':' . $val;
        } elseif ($val[0] === '/') {
            // Root-relative
            $abs = $base_origin . $val;
        } else {
            // Path-relative
            $abs = $base_origin . $base_dir . $val;
        }
        return $attr . '=' . $quote . $abs . $quote;
    },
    $html
);

// Collapse whitespace
$html = preg_replace('/[ \t]+/', ' ', $html);
$html = preg_replace('/\n{3,}/', "\n\n", $html);
$html = trim($html);

// Save to cache
@file_put_contents($cacheFile, $html);

// Output with explicit Content-Length (FujiNet can't handle chunked)
while (ob_get_level()) ob_end_clean();
header('Content-Type: text/html; charset=utf-8');
header('Content-Length: ' . strlen($html));
echo $html;
flush();
