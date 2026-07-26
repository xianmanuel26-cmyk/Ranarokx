# Ranarokx

One-shot helpers for:

1. **Hercules** on a Debian 12 game VPS (1 GB RAM OK)
2. **OpenKore** on a second Linux box, connected to that Hercules server

---

## 1) Hercules (game server)

On the **game** VPS:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo SERVER_IP=YOUR.PUBLIC.IP bash scripts/install-hercules-debian12.sh
```

Credentials: `/home/hercuser/hercules-credentials.txt`  
Defaults: `test`/`test123`, GM `admin`/`admin123`, ports **6900 / 6121 / 5121**.

The script applies the battle-tested fixes (swap, MariaDB TCP `127.0.0.1`, skip broken `setup_env.sh`, cmake `-j1`, IP patches, screen start).

---

## 2) OpenKore (bot host)

On your **other** Linux server:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo SERVER_IP=93.127.134.131 OK_USER=admin OK_PASS=admin123 \
  bash scripts/install-openkore-linux.sh
```

### Start

```bash
openkore-ranarokx
sudo -u openkore screen -r openkore
```

Or:

```bash
sudo -u openkore -i
cd /opt/openkore
perl ./openkore.pl
```

### Defaults

| Setting | Value |
|---------|--------|
| Target | `93.127.134.131:6900` |
| Account | `admin` / `admin123` |
| `serverType` | `kRO_RagexeRE_2018_11_21` (near Hercules PACKETVER 20190530) |
| Path | `/opt/openkore` |

### Login packet errors?

```bash
sudo SERVER_TYPE=kRO_RagexeRE_2020_03_04a SERVER_IP=93.127.134.131 \
  bash scripts/install-openkore-linux.sh
```

Ensure the bot host can reach TCP **6900, 6121, 5121** on the game server.

---

## Extra accounts (on Hercules host)

```bash
sudo bash scripts/create-game-account.sh myuser mypass
sudo bash scripts/create-game-account.sh gm2 secret 99
```

## Links

- [Hercules](https://github.com/HerculesWS/Hercules) · [Building](https://github.com/HerculesWS/Hercules/wiki/Building)
- [OpenKore](https://github.com/OpenKore/openkore) · [How to run](https://openkore.com/wiki/How_to_run_OpenKore)
