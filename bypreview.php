<?php
// php-preview.php
// Editor & Output PHP sederhana — aman digunakan di localhost

// Jika tombol Run ditekan
$output = '';
$code = isset($_POST['phpcode']) ? $_POST['phpcode'] : '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Tangkap output dari kode PHP
    ob_start();
    try {
        eval("?>" . $code);
    } catch (Throwable $e) {
        echo "Error: " . htmlspecialchars($e->getMessage());
    }
    $output = ob_get_clean();
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PHP Live Preview (Offline)</title>
<style>
    body {
        background: #0f172a;
        color: #e2e8f0;
        font-family: Arial, sans-serif;
        margin: 0;
        display: flex;
        height: 100vh;
        padding: 10px;
        gap: 10px;
    }
    .panel {
        flex: 1;
        display: flex;
        flex-direction: column;
        background: #1e293b;
        border-radius: 8px;
        padding: 10px;
    }
    h2 {
        margin-top: 0;
        font-size: 16px;
        color: #93c5fd;
    }
    textarea {
        flex: 1;
        resize: none;
        background: #0f172a;
        color: #e2e8f0;
        border: 1px solid #334155;
        border-radius: 6px;
        padding: 8px;
        font-family: monospace;
        font-size: 14px;
    }
    button {
        margin-top: 8px;
        padding: 8px 12px;
        background: #0284c7;
        color: white;
        border: none;
        border-radius: 6px;
        cursor: pointer;
    }
    .output {
        flex: 1;
        background: #fff;
        color: #000;
        border-radius: 6px;
        padding: 10px;
        overflow: auto;
    }
</style>
</head>
<body>
    <form class="panel" method="post">
        <h2>Editor PHP Created By 0xSHALL</h2>
        <textarea name="phpcode" placeholder="Tulis kode PHP di sini..."><?php echo htmlspecialchars($code ?: "<?php\necho 'Halo dunia!';\n?>"); ?></textarea>
        <button type="submit">Jalankan</button>
    </form>

    <div class="panel">
        <h2>Output</h2>
        <div class="output">
            <?php echo $output ?: '<em>Output akan muncul di sini setelah Anda klik Jalankan.</em>'; ?>
        </div>
    </div>
</body>
</html>
