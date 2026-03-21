<?php
/**
 * VBXE Image Converter for Atari XE/XL Web Browser
 *
 * Converts any web image to raw VBXE 8bpp format.
 * Output is always w px wide (VBXE overlay width).
 * Image is resized to fit within iw px, left-aligned with black padding.
 * Padding pixels = VBXE index 0 (transparent/black), image pixels = index 8-255.
 *
 * Requires: PHP GD extension + curl
 */

$url = isset($_GET['url']) ? $_GET['url'] : '';
$w = min(max(intval(isset($_GET['w']) ? $_GET['w'] : 320), 8), 320);
$h = min(max(intval(isset($_GET['h']) ? $_GET['h'] : 48), 8), 192);
$iw = min(max(intval(isset($_GET['iw']) ? $_GET['iw'] : 160), 8), $w);

if (empty($url)) {
    header('Content-Type: text/plain');
    echo "VBXE Image Converter\nUsage: ?url=IMAGE_URL&w=320&h=48&iw=160\n";
    exit;
}

$cacheDir = __DIR__ . '/vbxe_cache';
if (!is_dir($cacheDir)) @mkdir($cacheDir, 0755);
$hash = md5($url . $w . $h . $iw);
$cacheFile = $cacheDir . '/' . $hash . '.bin';

// Serve from cache if available (direct output, no redirect)
if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 3600) {
    header('Content-Type: application/octet-stream');
    header('Content-Length: ' . filesize($cacheFile));
    readfile($cacheFile);
    exit;
}

// Fetch image using curl (more reliable than file_get_contents)
function fetch_image($url) {
    // Try curl first
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_MAXREDIRS, 5);
        curl_setopt($ch, CURLOPT_TIMEOUT, 15);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0');
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        $data = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($data !== false && $code >= 200 && $code < 400) return $data;
    }
    // Fallback to file_get_contents
    $ctx = stream_context_create(['http' => [
        'timeout' => 15,
        'user_agent' => 'Mozilla/5.0',
        'follow_location' => true,
        'max_redirects' => 5
    ], 'ssl' => ['verify_peer' => false, 'verify_peer_name' => false]]);
    return @file_get_contents($url, false, $ctx);
}

$img_data = fetch_image($url);
if ($img_data === false) { http_response_code(502); echo "Cannot fetch image"; exit; }

$src = @imagecreatefromstring($img_data);
if (!$src) { http_response_code(400); echo "Invalid image: " . strlen($img_data) . "B"; exit; }

// Calculate image size maintaining aspect ratio, fitting within iw x h
$src_w = imagesx($src);
$src_h = imagesy($src);
$scale = min($iw / $src_w, $h / $src_h);
$img_w = max(1, intval($src_w * $scale));
$img_h = max(1, intval($src_h * $scale));

// Resize source image only (no padding canvas)
$resized = imagecreatetruecolor($img_w, $img_h);
imagecopyresampled($resized, $src, 0, 0, 0, 0, $img_w, $img_h, $src_w, $src_h);
imagedestroy($src);

// Quantize to 248 colors
imagetruecolortopalette($resized, true, 248);

// Left-aligned
$x_offset = 0;

// Build binary output: 2B width(LE) + 1B height + 768B palette + w*h pixels
$out = pack('v', $w) . chr($img_h);
$out .= str_repeat("\0", 24); // 8 reserved palette entries (indices 0-7)
$num_colors = imagecolorstotal($resized);
for ($i = 0; $i < 248; $i++) {
    if ($i < $num_colors) {
        $rgb = imagecolorsforindex($resized, $i);
        $out .= chr($rgb['red'] >> 1) . chr($rgb['green'] >> 1) . chr($rgb['blue'] >> 1);
    } else {
        $out .= "\0\0\0";
    }
}

// Write pixels: padding = byte 0 (VBXE transparent/black), image = palette index + 8
for ($y = 0; $y < $img_h; $y++) {
    // Left padding
    $out .= str_repeat("\0", $x_offset);
    // Image pixels
    for ($x = 0; $x < $img_w; $x++) {
        $out .= chr(imagecolorat($resized, $x, $y) + 8);
    }
    // Right padding
    $out .= str_repeat("\0", $w - $x_offset - $img_w);
}
imagedestroy($resized);

// Cache for next time
file_put_contents($cacheFile, $out);

// Output directly (FujiNet doesn't follow redirects!)
header('Content-Type: application/octet-stream');
header('Content-Length: ' . strlen($out));
echo $out;
