<?php
/**
 * VBXE Image Converter for Atari XE/XL Web Browser
 *
 * Converts any web image to raw VBXE 8bpp format.
 * Upload to: turiecfoto.sk/vbxe/vbxe.php
 *
 * Usage: vbxe.php?url=IMAGE_URL&w=160&h=100
 *
 * Response format (binary):
 *   2 bytes: width (16-bit little-endian)
 *   1 byte:  height
 *   768 bytes: palette (256 x R,G,B - 7-bit per channel for VBXE)
 *   w*h bytes: pixel data (palette indices, offset by 8 to preserve text colors)
 *
 * Requires: PHP GD extension (standard on most hosting)
 */

header('Content-Type: application/octet-stream');
header('Access-Control-Allow-Origin: *');

$url = isset($_GET['url']) ? $_GET['url'] : '';
$w = min(max(intval(isset($_GET['w']) ? $_GET['w'] : 160), 8), 320);
$h = min(max(intval(isset($_GET['h']) ? $_GET['h'] : 100), 8), 192);

if (empty($url)) {
    header('Content-Type: text/plain');
    echo "VBXE Image Converter\n";
    echo "Usage: ?url=IMAGE_URL&w=160&h=100\n";
    echo "Returns raw VBXE 8bpp image data.\n";
    exit;
}

// Download image
$ctx = stream_context_create([
    'http' => [
        'timeout' => 10,
        'user_agent' => 'VBXE-Browser/1.0'
    ]
]);

$img_data = @file_get_contents($url, false, $ctx);
if ($img_data === false) {
    header('HTTP/1.1 502 Bad Gateway');
    echo "Cannot fetch image";
    exit;
}

// Load image
$src = @imagecreatefromstring($img_data);
if (!$src) {
    header('HTTP/1.1 400 Bad Request');
    echo "Invalid image format";
    exit;
}

// Resize
$resized = imagecreatetruecolor($w, $h);
imagecopyresampled($resized, $src, 0, 0, 0, 0, $w, $h, imagesx($src), imagesy($src));
imagedestroy($src);

// Quantize to 248 colors (reserve 0-7 for text)
imagetruecolortopalette($resized, true, 248);

// Build output
$out = '';

// Header: width (16-bit LE), height (8-bit)
$out .= pack('v', $w);
$out .= chr($h);

// Palette: 256 entries x 3 bytes (R,G,B)
// First 8 entries: zeros (reserved for text colors)
$out .= str_repeat("\0", 8 * 3);

// Image palette at indices 8-255
$num_colors = imagecolorstotal($resized);
for ($i = 0; $i < 248; $i++) {
    if ($i < $num_colors) {
        $rgb = imagecolorsforindex($resized, $i);
        $out .= chr($rgb['red'] >> 1);   // 7-bit for VBXE
        $out .= chr($rgb['green'] >> 1);
        $out .= chr($rgb['blue'] >> 1);
    } else {
        $out .= "\0\0\0";
    }
}

// Pixel data: offset indices by 8
for ($y = 0; $y < $h; $y++) {
    for ($x = 0; $x < $w; $x++) {
        $idx = imagecolorat($resized, $x, $y);
        $out .= chr($idx + 8);
    }
}

imagedestroy($resized);

echo $out;
?>
