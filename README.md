# Ranarokx — Hercules on Debian 12 (1 GB VPS)

One-shot installer for [Hercules](https://github.com/HerculesWS/Hercules) on a fresh **Debian 12** VPS (**1 CPU / 1 GB RAM**).  
It includes every fix from a full manual install (swap, MariaDB TCP auth, CMake/Conan build, IP configs, test/GM accounts, screen start).

## One command (fresh OS)

As `root` or with `sudo`:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo bash scripts/install-hercules-debian12.sh
```

Optional overrides:

```bash
sudo SERVER_IP=93.127.134.131 \
  DB_PASS=ragnarok \
  PACKETVER=20190530 \
  bash scripts/install-hercules-debian12.sh
```

When it finishes, read:

`/home/hercuser/hercules-credentials.txt`

### Defaults created for you

| Item | Value |
|------|--------|
| Linux user | `hercuser` / `ragnarok` |
| MariaDB | `hercules` / `hercules` / `ragnarok` |
| Player | `test` / `test123` |
| GM | `admin` / `admin123` (group 99) |
| Ports | 6900, 6121, 5121 |

Point your RO client at **`SERVER_IP:6900`**. Client date must match server `PACKETVER` (see login-server log).

### After install

```bash
# Reattach server screen
sudo su - hercuser
screen -r hercules

# Or use systemd
sudo systemctl enable --now hercules
```

### What the script fixes (so you don’t hit our errors again)

1. **2 GB swap** before compile (avoids OOM on 1 GB)
2. **MariaDB low-mem** config + users for `localhost` **and** `127.0.0.1`
3. **`db_hostname: 127.0.0.1`** (avoids missing `/tmp/mysql.sock` with Conan client)
4. **Skips broken `setup_env.sh`** on login shells (`dirname -bash`); uses venv + conan + cmake manually
5. **Build `-j1`** for low RAM
6. Sets **login_ip / char_ip / map_ip** in main conf files (avoids virt NIC `192.168.122.x` confusion)
7. Starts servers in **screen** and installs a **systemd** unit

## Manual helpers

```bash
# Extra accounts
sudo bash scripts/create-game-account.sh myuser mypass
sudo bash scripts/create-game-account.sh gm2 secret 99
```

## Client notes

1. Match `PACKETVER` (rebuild with `PACKETVER=YYYYMMDD` if login rejects the client).
2. Patch client (NEMO etc.) for private server.
3. If you can’t connect from the internet, open/forward **6900, 6121, 5121** on the VPS/host (NAT VMs only have a private NIC like `192.168.122.33`).

## Links

- [Building](https://github.com/HerculesWS/Hercules/wiki/Building)
- [Installation](https://github.com/HerculesWS/Hercules/wiki/Installation)
- [herc.ws](https://herc.ws)
