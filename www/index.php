<?php
declare(strict_types=1);

$esc = static fn (mixed $value): string => htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');

$httpHost = $_SERVER['HTTP_HOST'] ?? 'localhost';
$siteHost = preg_replace('/:\d+$/', '', $httpHost) ?? $httpHost;
$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$webPort = (string) (getenv('WEB_PORT') ?: '80');

$baseHost = str_ends_with($siteHost, '.localhost') ? 'localhost' : $siteHost;
$webSuffix = $webPort === '80' ? '' : ':' . $webPort;
$baseOrigin = $scheme . '://' . $baseHost . $webSuffix;

$phpMyAdminPort = (string) (getenv('PMA_PORT') ?: '8080');
$mailpitPort = (string) (getenv('MAILPIT_UI_PORT') ?: '8025');
$jenkinsPort = (string) (getenv('JENKINS_PORT') ?: '8081');

$projects = [];
foreach (scandir(__DIR__) ?: [] as $entry) {
    if ($entry === '.' || $entry === '..' || $entry === 'index.php' || $entry[0] === '.') {
        continue;
    }

    $path = __DIR__ . DIRECTORY_SEPARATOR . $entry;
    if (!is_dir($path)) {
        continue;
    }

    $type = 'PHP project';
    if (is_file($path . '/wp-load.php')) {
        $type = 'WordPress';
    } elseif (
        (is_file($path . '/version.php') && is_file($path . '/lib/setup.php'))
        || (is_file($path . '/public/version.php') && is_file($path . '/public/lib/setup.php'))
    ) {
        $type = 'Moodle';
    } elseif (is_file($path . '/composer.json')) {
        $type = 'PHP + Composer';
    }

    $projects[$entry] = $type;
}
ksort($projects);

$dbState = 'Not reachable';
$dbVersion = '';
try {
    $pdo = new PDO(
        sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
            getenv('DB_HOST') ?: 'db',
            getenv('DB_PORT') ?: '3306',
            getenv('DB_DATABASE') ?: 'dev'
        ),
        getenv('DB_USERNAME') ?: 'dev',
        getenv('DB_PASSWORD') ?: 'dev',
        [PDO::ATTR_TIMEOUT => 2, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $dbState = 'Connected';
    $dbVersion = (string) $pdo->query('SELECT VERSION()')->fetchColumn();
} catch (Throwable) {
    // The dashboard should still render while MySQL is starting up.
}
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Local PHP Stack</title>
    <style>
        :root {
            --bg: #0b1020;
            --panel: #141b2d;
            --panel-2: #1b2438;
            --border: #293349;
            --text: #e8edf7;
            --muted: #9aa8c2;
            --accent: #8b9dff;
            --ok: #46d39a;
            --warn: #f2b35d;
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            min-height: 100vh;
            background:
                radial-gradient(900px 500px at 15% -10%, #23306b 0%, transparent 60%),
                radial-gradient(800px 400px at 100% 0%, #193c3d 0%, transparent 55%),
                var(--bg);
            color: var(--text);
            font: 15px/1.6 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
        }

        .wrap { max-width: 1100px; margin: 0 auto; padding: 48px 24px 64px; }

        header { display: flex; justify-content: space-between; gap: 24px; align-items: flex-start; flex-wrap: wrap; margin-bottom: 36px; }

        h1 { margin: 0 0 8px; font-size: 32px; letter-spacing: -0.02em; }
        h2 { margin: 0 0 16px; font-size: 18px; letter-spacing: -0.01em; }
        p { margin: 0; }

        .muted { color: var(--muted); }

        .status {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            border: 1px solid var(--border);
            background: var(--panel);
            border-radius: 999px;
            padding: 8px 14px;
            font-size: 13px;
            white-space: nowrap;
        }

        .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--warn); }
        .dot.ok { background: var(--ok); }

        section { margin-top: 32px; }

        .grid { display: grid; gap: 14px; }

        .services { grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }
        .projects { grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); }

        .card {
            display: block;
            background: linear-gradient(180deg, var(--panel) 0%, var(--panel-2) 100%);
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 18px;
            color: inherit;
            text-decoration: none;
            transition: transform .15s ease, border-color .15s ease;
        }

        a.card:hover { transform: translateY(-2px); border-color: #45557c; }

        .card h3 { margin: 10px 0 4px; font-size: 17px; }
        .card .url { color: var(--accent); font-size: 13px; word-break: break-all; }
        .card p { color: var(--muted); font-size: 13px; }

        .badge {
            display: inline-block;
            border-radius: 999px;
            border: 1px solid var(--border);
            background: #0f1628;
            color: var(--muted);
            font-size: 11px;
            letter-spacing: .04em;
            text-transform: uppercase;
            padding: 3px 9px;
        }

        .links { display: flex; gap: 14px; flex-wrap: wrap; margin-top: 14px; font-size: 13px; }
        .links a { color: var(--accent); text-decoration: none; }
        .links a:hover { text-decoration: underline; }

        .empty {
            border: 1px dashed var(--border);
            border-radius: 14px;
            padding: 24px;
            color: var(--muted);
            background: rgba(20, 27, 45, .5);
        }

        code {
            background: #0a1122;
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 2px 7px;
            color: #cfd8ff;
            font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        }

        .commands { display: grid; gap: 8px; margin-top: 14px; }

        footer { margin-top: 48px; padding-top: 20px; border-top: 1px solid var(--border); color: var(--muted); font-size: 13px; }
    </style>
</head>
<body>
<div class="wrap">
    <header>
        <div>
            <h1>Local PHP Stack</h1>
            <p class="muted">Apache, PHP <?= $esc(PHP_VERSION) ?>, MySQL, phpMyAdmin and Mailpit, ready for any PHP project.</p>
        </div>
        <div class="status">
            <span class="dot <?= $dbState === 'Connected' ? 'ok' : '' ?>"></span>
            MySQL <?= $esc($dbState) ?><?= $dbVersion !== '' ? ' ' . $esc($dbVersion) : '' ?>
        </div>
    </header>

    <section>
        <h2>Services</h2>
        <div class="grid services">
            <a class="card" href="<?= $esc("http://{$baseHost}:{$phpMyAdminPort}/") ?>">
                <span class="badge">Database UI</span>
                <h3>phpMyAdmin</h3>
                <span class="url"><?= $esc($baseHost) ?>:<?= $esc($phpMyAdminPort) ?></span>
                <p>Browse schemas, run SQL and import dumps.</p>
            </a>
            <a class="card" href="<?= $esc("http://{$baseHost}:{$mailpitPort}/") ?>">
                <span class="badge">Mail</span>
                <h3>Mailpit</h3>
                <span class="url"><?= $esc($baseHost) ?>:<?= $esc($mailpitPort) ?></span>
                <p>Every email from PHP mail() is captured here. SMTP is on port 1025.</p>
            </a>
            <a class="card" href="<?= $esc("http://{$baseHost}:{$jenkinsPort}/") ?>">
                <span class="badge">CI (optional)</span>
                <h3>Jenkins</h3>
                <span class="url"><?= $esc($baseHost) ?>:<?= $esc($jenkinsPort) ?></span>
                <p>Start it with <code>bash stack.sh ci-up</code>.</p>
            </a>
            <div class="card">
                <span class="badge">Web server</span>
                <h3>Apache + PHP</h3>
                <span class="url"><?= $esc($baseHost) ?><?= $esc($webSuffix) ?></span>
                <p>Drop a project into <code>www/</code> and open it via path or subdomain.</p>
            </div>
        </div>
    </section>

    <section>
        <h2>Projects (<?= count($projects) ?>)</h2>
        <?php if ($projects === []): ?>
            <div class="empty">
                <p>No projects yet. Create one from the repository root:</p>
                <div class="commands">
                    <div><code>bash stack.sh wp blog</code> &nbsp; WordPress with database and admin user</div>
                    <div><code>bash stack.sh moodle learn</code> &nbsp; Moodle with database and admin user</div>
                    <div>Or copy any PHP project into <code>www/your-project/</code>.</div>
                </div>
            </div>
        <?php else: ?>
            <div class="grid projects">
                <?php foreach ($projects as $name => $type): ?>
                    <?php
                    $pathUrl = $baseOrigin . '/' . rawurlencode($name) . '/';
                    $safeForSubdomain = preg_match('/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/', $name) === 1;
                    $subdomainUrl = $scheme . '://' . $name . '.localhost' . $webSuffix . '/';
                    $usesCanonicalSubdomain = in_array($type, ['WordPress', 'Moodle'], true);
                    ?>
                    <article class="card">
                        <span class="badge"><?= $esc($type) ?></span>
                        <h3><?= $esc($name) ?></h3>
                        <div class="links">
                            <?php if ($safeForSubdomain): ?>
                                <a href="<?= $esc($subdomainUrl) ?>">Open <?= $esc($name) ?>.localhost</a>
                            <?php endif; ?>
                            <?php if (!$usesCanonicalSubdomain): ?>
                                <a href="<?= $esc($pathUrl) ?>">Open via path</a>
                            <?php endif; ?>
                        </div>
                    </article>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </section>

    <footer>
        Projects live in <code>www/</code>. Stack commands are in <code>stack.sh</code>; usage notes are in <code>README.md</code>.
        Services bind to localhost by default and this stack uses development credentials. Do not expose it to the internet.
    </footer>
</div>
</body>
</html>
