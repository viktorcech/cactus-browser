<?php
/**
 * VBXE Image Converter for Atari XE/XL Web Browser
 *
 * Converts any web image to raw VBXE 8bpp format.
 * Writes output to static .bin file and serves it directly.
 * This avoids Transfer-Encoding: chunked (FujiNet can't handle it).
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

// Serve from cache if available
if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 3600) {
    // Serve static file - openresty won't chunk static readfile with ob disabled
    while (ob_get_level()) ob_end_clean();
    header('Content-Type: application/octet-stream');
    header('Content-Length: ' . filesize($cacheFile));
    header('Connection: close');
    readfile($cacheFile);
    exit;
}

// Fetch image using curl
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_MAXREDIRS, 5);
curl_setopt($ch, CURLOPT_TIMEOUT, 15);
curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0');
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
$img_data = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_error($ch);
curl_close($ch);

if ($img_data === false || $code >= 400) {
    http_response_code(502);
    echo "Cannot fetch image (HTTP $code $err) url=$url";
    exit;
}

$src = @imagecreatefromstring($img_data);
if (!$src) { http_response_code(400); echo "Invalid image: " . strlen($img_data) . "B"; exit; }

// Calculate image size maintaining aspect ratio, center on black canvas
$src_w = imagesx($src);
$src_h = imagesy($src);
$scale = min($iw / $src_w, $h / $src_h);
$img_w = max(1, intval($src_w * $scale));
$img_h = max(1, intval($src_h * $scale));

// Resize
$resized = imagecreatetruecolor($img_w, $img_h);
imagecopyresampled($resized, $src, 0, 0, 0, 0, $img_w, $img_h, $src_w, $src_h);
imagedestroy($src);

// Center on full-size black canvas (like reference converter)
$canvas = imagecreatetruecolor($w, $h);
imagefill($canvas, 0, 0, imagecolorallocate($canvas, 0, 0, 0));
$left = intval(($w - $img_w) / 2);
$top = intval(($h - $img_h) / 2);
imagecopy($canvas, $resized, $left, $top, 0, 0, $img_w, $img_h);
imagedestroy($resized);

// Quantize to 248 colors
imagetruecolortopalette($canvas, true, 248);

// Build binary: 2B width(LE) + 1B height + 768B palette + w*h pixels
// Header — always full canvas height
$out = pack('v', $w) . chr($h);

// Palette: 8 reserved (24 bytes zero) + up to 248 colors
$pal = str_repeat("\0", 24);
$num_colors = imagecolorstotal($canvas);
for ($i = 0; $i < $num_colors; $i++) {
    $rgb = imagecolorsforindex($canvas, $i);
    $pal .= chr($rgb['red'] >> 1) . chr($rgb['green'] >> 1) . chr($rgb['blue'] >> 1);
}
$pal .= str_repeat("\0", 768 - strlen($pal));  // pad to 768 bytes
$out .= $pal;

// Pixels: full canvas, no padding needed (canvas is already $w wide)
for ($y = 0; $y < $h; $y++) {
    $row = '';
    for ($x = 0; $x < $w; $x++) {
        $row .= chr(imagecolorat($canvas, $x, $y) + 8);
    }
    $out .= $row;
}
imagedestroy($canvas);

// Save to cache file
file_put_contents($cacheFile, $out);

// Serve the file
while (ob_get_level()) ob_end_clean();
header('Content-Type: application/octet-stream');
header('Content-Length: ' . strlen($out));
header('Connection: close');
echo $out;
flush();
