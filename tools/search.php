<?php
/**
 * Search proxy for VBXE Browser (Atari 8-bit)
 * Takes search query, fetches DuckDuckGo lite results,
 * returns simple HTML the browser can render.
 *
 * Usage: https://turiecfoto.sk/search.php?q=atari+800xl
 * Atari: N:http://turiecfoto.sk/search.php?q=atari+800xl
 */

$query = trim($_GET['q'] ?? '');
if (!$query) {
    header('Content-Type: text/html; charset=utf-8');
    $html = '<html><body><h1>VBXE Search</h1>'
          . '<p>Usage: ?q=your+search+terms</p></body></html>';
    header('Content-Length: ' . strlen($html));
    echo $html;
    exit;
}

// Fetch DuckDuckGo Lite results (simple HTML, stable format)
$ddg_url = 'https://lite.duckduckgo.com/lite/';
$post_data = http_build_query(['q' => $query]);

$ctx = stream_context_create([
    'http' => [
        'method' => 'POST',
        'header' => "Content-Type: application/x-www-form-urlencoded\r\n"
                   . "User-Agent: Mozilla/5.0 (compatible; VBXEBrowser/1.0)\r\n"
                   . "Accept: text/html\r\n",
        'content' => $post_data,
        'timeout' => 15,
        'follow_location' => true,
    ],
    'ssl' => [
        'verify_peer' => false,
        'verify_peer_name' => false,
    ],
]);

$ddg_html = @file_get_contents($ddg_url, false, $ctx);

if ($ddg_html === false) {
    // Fallback: try GET request to HTML version
    $ddg_url2 = 'https://html.duckduckgo.com/html/?q=' . urlencode($query);
    $ctx2 = stream_context_create([
        'http' => [
            'header' => "User-Agent: Mozilla/5.0 (compatible; VBXEBrowser/1.0)\r\n"
                       . "Accept: text/html\r\n",
            'timeout' => 15,
            'follow_location' => true,
        ],
        'ssl' => [
            'verify_peer' => false,
            'verify_peer_name' => false,
        ],
    ]);
    $ddg_html = @file_get_contents($ddg_url2, false, $ctx2);
}

if ($ddg_html === false) {
    header('Content-Type: text/html; charset=utf-8');
    $html = '<html><body><h1>Search Error</h1>'
          . '<p>Cannot reach search engine. Try again later.</p></body></html>';
    header('Content-Length: ' . strlen($html));
    echo $html;
    exit;
}

// Parse DuckDuckGo lite results
// Format: <a> links with class "result-link" or inside result snippets
$results = [];

// DuckDuckGo lite format: results in table rows
// Each result has: link text (title), URL, and snippet
if (preg_match_all('/<a[^>]+rel="nofollow"[^>]+href="([^"]+)"[^>]*>\s*(.*?)\s*<\/a>/si', $ddg_html, $matches, PREG_SET_ORDER)) {
    foreach ($matches as $m) {
        $url = trim($m[1]);
        $title = strip_tags(trim($m[2]));
        if (!$title || !$url) continue;
        // Skip DuckDuckGo internal links
        if (strpos($url, 'duckduckgo.com') !== false) continue;
        if (strpos($url, '/lite/') === 0) continue;
        // Clean up URL (DDG sometimes wraps in redirect)
        if (preg_match('/uddg=([^&]+)/', $url, $um)) {
            $url = urldecode($um[1]);
        }
        $results[] = ['url' => $url, 'title' => $title, 'snippet' => ''];
    }
}

// Try to extract snippets from <td> elements following each result
if (preg_match_all('/<td[^>]*class="result-snippet"[^>]*>(.*?)<\/td>/si', $ddg_html, $snip_matches)) {
    foreach ($snip_matches[1] as $i => $snippet) {
        if (isset($results[$i])) {
            $results[$i]['snippet'] = trim(strip_tags($snippet));
        }
    }
}

// If no results from lite format, try html.duckduckgo.com format
if (empty($results)) {
    if (preg_match_all('/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>/si', $ddg_html, $matches, PREG_SET_ORDER)) {
        foreach ($matches as $m) {
            $url = trim($m[1]);
            $title = strip_tags(trim($m[2]));
            if (!$title || !$url) continue;
            if (preg_match('/uddg=([^&]+)/', $url, $um)) {
                $url = urldecode($um[1]);
            }
            $results[] = ['url' => $url, 'title' => $title, 'snippet' => ''];
        }
    }
    if (preg_match_all('/<a[^>]+class="result__snippet"[^>]*>(.*?)<\/a>/si', $ddg_html, $snip_matches)) {
        foreach ($snip_matches[1] as $i => $snippet) {
            if (isset($results[$i])) {
                $results[$i]['snippet'] = trim(strip_tags($snippet));
            }
        }
    }
}

// Limit results (Atari can't display too many)
$results = array_slice($results, 0, 15);

// Build simple HTML output
$safe_query = htmlspecialchars($query);
$out = "<html><body>\n";
$out .= "<h1>Search: {$safe_query}</h1>\n";

if (empty($results)) {
    $out .= "<p>No results found for \"{$safe_query}\".</p>\n";
    $out .= "<p>Try different search terms.</p>\n";
} else {
    $out .= "<p>" . count($results) . " results:</p>\n";
    $out .= "<hr>\n";
    foreach ($results as $r) {
        $safe_title = htmlspecialchars($r['title']);
        $safe_url = htmlspecialchars($r['url']);
        $out .= "<p><b><a href=\"{$safe_url}\">{$safe_title}</a></b><br>\n";
        if ($r['snippet']) {
            $out .= htmlspecialchars($r['snippet']) . "<br>\n";
        }
        // Show short URL in italics
        $short = parse_url($r['url'], PHP_URL_HOST) ?: $r['url'];
        $out .= "<i>{$short}</i></p>\n";
        $out .= "<hr>\n";
    }
}

$out .= "</body></html>\n<!--";

// Output with explicit Content-Length (FujiNet can't handle chunked)
// Force HTTP/1.0 response to prevent chunked transfer encoding
while (ob_get_level()) ob_end_clean();
header('HTTP/1.0 200 OK');
header('Content-Type: text/html; charset=utf-8');
header('Content-Length: ' . strlen($out));
header('Connection: close');
echo $out;
flush();
