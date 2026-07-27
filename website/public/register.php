<?php
declare(strict_types=1);

require dirname(__DIR__) . '/lib/bootstrap.php';

$site = $config['site'];
$siteName = $site['name'];
$errors = [];
$success = null;
$form = [
    'userid' => '',
    'email' => '',
    'sex' => 'M',
];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!csrf_ok($_POST['csrf'] ?? null)) {
        $errors[] = 'Invalid session token. Refresh and try again.';
    } else {
        $userid = trim((string) ($_POST['userid'] ?? ''));
        $password = (string) ($_POST['password'] ?? '');
        $confirm = (string) ($_POST['password_confirm'] ?? '');
        $email = trim((string) ($_POST['email'] ?? ''));
        $sex = (string) ($_POST['sex'] ?? 'M');

        $form['userid'] = $userid;
        $form['email'] = $email;
        $form['sex'] = $sex === 'F' ? 'F' : 'M';

        $minU = (int) $site['min_userid'];
        $maxU = (int) $site['max_userid'];
        $minP = (int) $site['min_password'];
        $maxP = (int) $site['max_password'];

        if (!preg_match('/^[A-Za-z0-9_]+$/', $userid) || strlen($userid) < $minU || strlen($userid) > $maxU) {
            $errors[] = "Userid must be {$minU}–{$maxU} characters (letters, numbers, underscore).";
        }
        if (strlen($password) < $minP || strlen($password) > $maxP) {
            $errors[] = "Password must be {$minP}–{$maxP} characters.";
        }
        if ($password !== $confirm) {
            $errors[] = 'Passwords do not match.';
        }
        if ($email === '') {
            $email = strtolower($userid) . '@localhost';
        } elseif (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 39) {
            $errors[] = 'Email must be valid and at most 39 characters (Hercules limit).';
        }
        if (!in_array($sex, ['M', 'F'], true)) {
            $errors[] = 'Sex must be M or F.';
        }

        // Simple rate limit: 1 attempt / 3 seconds per session
        $now = time();
        if (isset($_SESSION['reg_last']) && ($now - (int) $_SESSION['reg_last']) < 3) {
            $errors[] = 'Please wait a moment before trying again.';
        }

        if (!$errors) {
            $_SESSION['reg_last'] = $now;
            try {
                $pdo = db($config);
                $check = $pdo->prepare('SELECT 1 FROM `login` WHERE `userid` = ? LIMIT 1');
                $check->execute([$userid]);
                if ($check->fetch()) {
                    $errors[] = 'That userid is already taken.';
                } else {
                    $stored = !empty($site['password_md5']) ? md5($password) : $password;
                    $ins = $pdo->prepare(
                        'INSERT INTO `login` (`userid`, `user_pass`, `sex`, `email`, `group_id`)
                         VALUES (?, ?, ?, ?, 0)'
                    );
                    $ins->execute([$userid, $stored, $sex, $email]);
                    $success = 'Account created. You can log in to the game now.';
                    $form = ['userid' => '', 'email' => '', 'sex' => 'M'];
                    $_SESSION['csrf'] = bin2hex(random_bytes(32));
                }
            } catch (Throwable $e) {
                $errors[] = 'Registration failed. Check database settings on the server.';
            }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Register — <?= h($siteName) ?></title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&family=Source+Sans+3:wght@400;600&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
  <div class="shell">
    <header class="topnav">
      <a class="brand-mark" href="/"><?= h($siteName) ?></a>
      <a href="/">Home</a>
    </header>

    <section class="panel">
      <h2>Create account</h2>
      <p class="lead">Your userid and password are used in the Ragnarok client login screen.</p>

      <?php if ($success): ?>
        <div class="flash ok"><?= h($success) ?></div>
      <?php endif; ?>

      <?php foreach ($errors as $err): ?>
        <div class="flash err"><?= h($err) ?></div>
      <?php endforeach; ?>

      <form method="post" action="/register.php" autocomplete="off">
        <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">

        <label for="userid">Userid</label>
        <input id="userid" name="userid" required maxlength="23"
               pattern="[A-Za-z0-9_]{4,23}"
               value="<?= h($form['userid']) ?>">

        <label for="password">Password</label>
        <input id="password" name="password" type="password" required maxlength="31">

        <label for="password_confirm">Confirm password</label>
        <input id="password_confirm" name="password_confirm" type="password" required maxlength="31">

        <label for="email">Email (optional)</label>
        <input id="email" name="email" type="email" maxlength="39"
               value="<?= h($form['email']) ?>">

        <label for="sex">Sex</label>
        <select id="sex" name="sex">
          <option value="M" <?= $form['sex'] === 'M' ? 'selected' : '' ?>>Male</option>
          <option value="F" <?= $form['sex'] === 'F' ? 'selected' : '' ?>>Female</option>
        </select>

        <div class="actions">
          <button class="btn btn-gold" type="submit">Register</button>
          <a class="btn" href="/">Back</a>
        </div>
      </form>
    </section>

    <footer class="foot">&copy; <?= date('Y') ?> <?= h($siteName) ?></footer>
  </div>
</body>
</html>
