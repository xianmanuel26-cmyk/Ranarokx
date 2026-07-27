# Ranarokx

## Hosts (source of truth)

| # | Role | Where | What runs here |
|---|------|--------|----------------|
| **1** | **Game** | Linux VPS | Hercules, MariaDB, registration site |
| **2** | **Client** | Windows VPS | RO client (+ Cursor worker `windows-ro`) |
| **3** | **Bot** | Android **Termux** | OpenKore |

Do **not** treat a separate “OpenKore Linux VPS” as part of this project. That old layout is retired.

**Where to run Cursor workers / installs**

| Task | Run on |
|------|--------|
| Hercules, registration site, MariaDB | **#1 Linux** |
| RO client setup | **#2 Windows** |
| OpenKore bot | **#3 Termux** (phone) |

---

## 1) Hercules — Linux (#1)

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo SERVER_IP=173.208.138.66 bash scripts/install-hercules-debian12.sh
```

| Item | Value |
|------|--------|
| Public IP | **`173.208.138.66`** |
| Credentials | `/home/hercuser/hercules-credentials.txt` |
| Accounts | `test`/`test123`, GM `admin`/`admin123` |
| Ports | **6900 / 6121 / 5121** (TCP) |
| PACKETVER | **20190530** |

Extra accounts:

```bash
sudo bash scripts/create-game-account.sh myuser mypass
sudo bash scripts/create-game-account.sh gm2 secret 99
```

---

## 2) Registration site — Linux (#1)

```bash
cd /path/to/Ranarokx
sudo bash scripts/install-registration-site.sh
```

Open `http://173.208.138.66/register.php` (TCP **80** on host/NAT).

| Item | Path / note |
|------|-------------|
| Web root | `/var/www/ranarokx/public` |
| Config | `/var/www/ranarokx/config.php` |
| DB | `hercules` / `hercules` / `ragnarok` @ `127.0.0.1` |

Passwords are **plaintext** (matches Hercules defaults). For MD5 login-server mode, set `'password_md5' => true` in `config.php`.

---

## 3) OpenKore — Termux (#3)

Primary bot host is **Termux on your phone**, not Windows and not a second Linux VPS.

Guide: **[docs/termux-openkore.md](docs/termux-openkore.md)**

Summary:
- Clone OpenKore in Termux, point `servers.txt` at Linux **#1 public IP**
- `serverType kRO_RagexeRE_2018_11_21`, patched `recvpackets`, UTF-8 `quests.txt`
- Do **not** set `forceMapIP 127.0.0.1` on Termux (that is only for same-host Linux)
- Needs TCP **6900 / 6121 / 5121** reachable from the phone network

Optional fallback only (same Linux #1 box): `scripts/install-openkore-linux.sh` with `SERVER_IP=127.0.0.1`.

---

## 4) RO client — Windows (#2)

- Client matching PACKETVER **20190530**
- Cursor worker: **`windows-ro`**
- Connect to Linux **#1 public IP** (ports 6900 / 6121 / 5121)

Do **not** install Hercules, MariaDB, registration, or OpenKore on Windows.

---

## Repo map

| Path | Purpose | Host |
|------|---------|------|
| `scripts/install-hercules-debian12.sh` | Game server | #1 Linux |
| `scripts/install-registration-site.sh` | Web register | #1 Linux |
| `scripts/create-game-account.sh` | CLI accounts | #1 Linux |
| `scripts/install-openkore-linux.sh` | Optional same-host bot | #1 Linux only |
| `docs/termux-openkore.md` | Phone OpenKore | #3 Termux |
| `website/` | Registration UI | deployed on #1 |
| `systemd/hercules.service` | Optional systemd unit | #1 Linux |

## Links

- [Hercules](https://github.com/HerculesWS/Hercules) · [Building](https://github.com/HerculesWS/Hercules/wiki/Building)
- [OpenKore](https://github.com/OpenKore/openkore) · [How to run](https://openkore.com/wiki/How_to_run_OpenKore)
