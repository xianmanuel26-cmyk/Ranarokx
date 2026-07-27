<?php
/**
 * Copy to config.php on the Hercules host and fill in DB credentials.
 * Prefer values from /home/hercuser/hercules-credentials.txt
 */
declare(strict_types=1);

return [
    'db' => [
        'host' => '127.0.0.1',
        'port' => 3306,
        'name' => 'hercules',
        'user' => 'hercules',
        'pass' => 'ragnarok',
        'charset' => 'utf8mb4',
    ],
    'site' => [
        'name' => 'Ranarokx',
        'tagline' => 'Classic Midgard. Register and enter the realm.',
        // Plaintext passwords match Hercules default + create-game-account.sh
        'password_md5' => false,
        'min_userid' => 4,
        'max_userid' => 23,
        'min_password' => 4,
        'max_password' => 31,
    ],
];
