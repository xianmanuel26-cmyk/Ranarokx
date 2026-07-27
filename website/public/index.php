<?php
declare(strict_types=1);

require dirname(__DIR__) . '/lib/bootstrap.php';

$siteName = $config['site']['name'];
$tagline = $config['site']['tagline'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= h($siteName) ?> — Classic Ragnarok</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&family=Source+Sans+3:wght@400;600&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
  <div class="shell">
    <header class="topnav">
      <a class="brand-mark" href="/"><?= h($siteName) ?></a>
      <a href="/register.php">Create account</a>
    </header>

    <main class="hero">
      <h1><?= h($siteName) ?></h1>
      <p><?= h($tagline) ?></p>
      <div class="cta-row">
        <a class="btn btn-gold" href="/register.php">Register</a>
        <a class="btn" href="#info">Server info</a>
      </div>
    </main>

    <section id="info" class="panel" style="width:min(560px,100%)">
      <h2>Enter Midgard</h2>
      <p class="lead">Create a game account, then log in with the RO client (Windows) or OpenKore (Termux).</p>
      <p class="lead" style="margin-bottom:0">Ports: <strong>6900</strong> / <strong>6121</strong> / <strong>5121</strong> · PACKETVER <strong>20190530</strong></p>
    </section>

    <footer class="foot">&copy; <?= date('Y') ?> <?= h($siteName) ?></footer>
  </div>
</body>
</html>
