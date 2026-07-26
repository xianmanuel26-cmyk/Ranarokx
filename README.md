# Ranarokx

Helpers for a private **Hercules** RO server and an **OpenKore** bot host.

## 1) Hercules (game server) — Debian 12

On the game VPS:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo SERVER_IP=YOUR.PUBLIC.IP bash scripts/install-hercules-debian12.sh
```

(See `scripts/install-hercules-debian12.sh` when that PR is merged, or use branch `cursor/hercules-debian-install-530f`.)

Defaults: player `test`/`test123`, GM `admin`/`admin123`, ports `6900` / `6121` / `5121`.

---

## 2) OpenKore (bot client) — other Linux box

On your **second** Linux server (bot host), point OpenKore at Hercules:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx
sudo bash scripts/install-openkore-linux.sh
```

Or with overrides:

```bash
sudo SERVER_IP=93.127.134.131 \
  OK_USER=admin \
  OK_PASS=admin123 \
  bash scripts/install-openkore-linux.sh
```

### Start OpenKore

```bash
# background (screen)
openkore-ranarokx
sudo -u openkore screen -r openkore

# or foreground
sudo -u openkore -i
cd /opt/openkore
perl ./openkore.pl
```

### Defaults

| Setting | Value |
|---------|--------|
| Hercules IP | `93.127.134.131:6900` |
| Account | `admin` / `admin123` |
| `serverType` | `kRO_RagexeRE_2018_11_21` (near PACKETVER 20190530) |
| Install path | `/opt/openkore` |

### If it fails to log in

Try a nearby serverType:

```bash
sudo SERVER_TYPE=kRO_RagexeRE_2020_03_04a bash scripts/install-openkore-linux.sh
```

Or edit `/opt/openkore/tables/servers.txt` (block between `RANAROKX_BEGIN` / `RANAROKX_END`) and `/opt/openkore/control/config.txt`.

Make sure the bot host can reach the game server TCP ports **6900, 6121, 5121**.

---

## Links

- [Hercules](https://github.com/HerculesWS/Hercules)
- [OpenKore](https://github.com/OpenKore/openkore)
- [OpenKore wiki — How to run](https://openkore.com/wiki/How_to_run_OpenKore)
