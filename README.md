# Ranarokx

## Servers (current setup)

| # | Role | OS | What runs here |
|---|------|-----|----------------|
| **1** | **Game host** | Linux | Hercules, MariaDB, registration site, optional OpenKore |
| **2** | **Client host** | Windows | RO client (+ Cursor worker `windows-ro`) |

There is **no third Linux “bot VPS”** in this setup. Anything that says “OpenKore VPS” or `vps-emydRO` as a separate game box is outdated.

**Cursor workers**
- Linux worker → must be on server **#1** (Hercules host) for installs/deploys
- Windows worker → server **#2** (client only)

---

One-shot helpers:

1. **Hercules** on the Linux game host
2. **Registration website** on that same Linux host
3. **OpenKore** (optional) on that same Linux host (`127.0.0.1`)

---

## 1) Hercules (Linux game host)

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo SERVER_IP=YOUR.PUBLIC.IP bash scripts/install-hercules-debian12.sh
```

Credentials: `/home/hercuser/hercules-credentials.txt`  
Defaults: `test`/`test123`, GM `admin`/`admin123`, ports **6900 / 6121 / 5121**.

---

## 2) Registration site (same Linux game host)

Creates accounts in the Hercules `login` table.

```bash
cd /path/to/Ranarokx
sudo bash scripts/install-registration-site.sh
```

Then open `http://YOUR.PUBLIC.IP/register.php` (TCP **80** must be open on host/NAT).

| Item | Path / note |
|------|-------------|
| Web root | `/var/www/ranarokx/public` |
| Config | `/var/www/ranarokx/config.php` |
| DB | `hercules` / `hercules` / `ragnarok` @ `127.0.0.1` |

Passwords are stored **plaintext** to match Hercules defaults. If you enable MD5 in login-server, set `'password_md5' => true` in `config.php`.

### Extra accounts (CLI)

```bash
sudo bash scripts/create-game-account.sh myuser mypass
sudo bash scripts/create-game-account.sh gm2 secret 99
```

---

## 3) OpenKore (optional, same Linux game host)

Run on the **Hercules host**, not Windows:

```bash
cd /path/to/Ranarokx
sudo SERVER_IP=127.0.0.1 OK_USER=admin OK_PASS=admin123 \
  bash scripts/install-openkore-linux.sh
```

`SERVER_IP=127.0.0.1` is required when OpenKore is on the same machine (avoids hairpin NAT). The installer also sets `forceMapIP 127.0.0.1`.

### Start

```bash
openkore-ranarokx
sudo -u openkore screen -r openkore
```

| Setting | Value |
|---------|--------|
| Target | `127.0.0.1:6900` |
| Account | `admin` / `admin123` |
| `serverType` | `kRO_RagexeRE_2018_11_21` (near PACKETVER 20190530) |
| Path | `/opt/openkore` |

---

## 4) Windows client host

- RO client for PACKETVER **20190530**
- Cursor worker name: **`windows-ro`**
- Points at the Linux game host **public IP** (ports 6900 / 6121 / 5121)

Do **not** install Hercules, MariaDB, or the registration site on Windows.

## Links

- [Hercules](https://github.com/HerculesWS/Hercules) · [Building](https://github.com/HerculesWS/Hercules/wiki/Building)
- [OpenKore](https://github.com/OpenKore/openkore) · [How to run](https://openkore.com/wiki/How_to_run_OpenKore)
