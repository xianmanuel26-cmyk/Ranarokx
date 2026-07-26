# Ranarokx — Hercules on Debian 12 (1 GB VPS)

Install guide and automated script for [Hercules](https://github.com/HerculesWS/Hercules) on a fresh **Debian 12 64-bit** VPS with **1 CPU / 1 GB RAM**.

## Reality check for 1 GB RAM

Hercules can *run* on ~128 MB+, but **compiling** (especially the modern CMake + Conan build) needs more. This setup:

- Creates a **2 GB swap file** before building
- Builds with **1 job** (`-j1`) to avoid OOM kills
- Tunes **MariaDB** for low memory

Expect a long first compile (often 30–90+ minutes on 1 vCPU). For a few players this VPS is fine; large populations will need more RAM/CPU.

## Quick install (recommended)

On your Debian 12 VPS as root:

```bash
# 1) Get this repo
apt-get update
apt-get install -y git
git clone https://github.com/xianmanuel26-cmyk/Ranarokx.git
cd Ranarokx

# 2) Set your public IP (clients connect here), then install
export SERVER_IP="YOUR.PUBLIC.IP"
# optional:
# export DB_PASS='strong-db-password'
# export PACKETVER=20211103          # must match your RO client
# export ENABLE_RENEWAL=ON           # or OFF for pre-renewal
# export INTER_PASS='change-me'      # change before going public

sudo bash scripts/install-hercules-debian12.sh
```

When it finishes, credentials are in `/home/hercuser/hercules-credentials.txt`.

### Start the server

```bash
su - hercuser
cd ~/Hercules
./athena-start start
```

Stop / restart:

```bash
./athena-start stop
./athena-start restart
```

Open firewall ports if needed: **6900**, **6121**, **5121** (TCP).

---

## Manual install (step by step)

Use this if you prefer typing each command yourself.

### 1. Swap (required on 1 GB)

```bash
fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl -w vm.swappiness=10
```

### 2. Packages

```bash
apt-get update
apt-get install -y git cmake ninja-build make gcc g++ python3 python3-venv \
  mariadb-server mariadb-client screen dos2unix zlib1g-dev libpcre3-dev \
  libssl-dev pkg-config openssl
```

### 3. Low-memory MariaDB

```bash
cat >/etc/mysql/mariadb.conf.d/99-hercules-lowmem.cnf <<'EOF'
[mysqld]
performance_schema = OFF
innodb_buffer_pool_size = 64M
innodb_log_buffer_size = 8M
key_buffer_size = 8M
tmp_table_size = 16M
max_heap_table_size = 16M
max_connections = 40
table_open_cache = 200
thread_cache_size = 4
query_cache_type = 0
skip_name_resolve = ON
EOF
systemctl enable --now mariadb
systemctl restart mariadb
```

### 4. Non-root user + clone

```bash
useradd -m -s /bin/bash hercuser
passwd hercuser
su - hercuser
git clone --branch stable --depth 1 https://github.com/HerculesWS/Hercules.git ~/Hercules
cd ~/Hercules
cp -a conf/import-tmpl conf/import
```

### 5. Database

As root:

```bash
mysql -u root <<'SQL'
CREATE DATABASE hercules CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'hercules'@'localhost' IDENTIFIED BY 'CHANGE_THIS_PASSWORD';
GRANT ALL PRIVILEGES ON hercules.* TO 'hercules'@'localhost';
FLUSH PRIVILEGES;
SQL

cd /home/hercuser/Hercules/sql-files
mysql -u root hercules < main.sql
mysql -u root hercules < logs.sql
```

`main.sql` already creates the inter-server account `s1` / `p1` (gender `S`).

### 6. Config

Edit SQL credentials in:

`~/Hercules/conf/global/sql_connection.conf`

```conf
db_hostname: "127.0.0.1"
db_port: 3306
db_username: "hercules"
db_password: "CHANGE_THIS_PASSWORD"
db_database: "hercules"
```

Set public IPs in import files:

`conf/import/char-server.conf`

```conf
char_configuration: {
	server_name: "Ranarokx"
	inter: {
		userid: "s1"
		passwd: "p1"
		login_ip: "127.0.0.1"
		char_ip: "YOUR.PUBLIC.IP"
	}
}
```

`conf/import/map-server.conf`

```conf
map_configuration: {
	inter: {
		userid: "s1"
		passwd: "p1"
		char_ip: "127.0.0.1"
		map_ip: "YOUR.PUBLIC.IP"
	}
}
```

### 7. Build (current Hercules = CMake + Conan)

As `hercuser`:

```bash
cd ~/Hercules
. ./setup_env.sh --build-type RelWithDebInfo

# optional: match your client date, and/or disable renewal
cmake -S . -B build \
  -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=cmake_modules/conan_provider.cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DENABLE_TESTING=OFF \
  -DENABLE_RENEWAL=ON \
  -G Ninja
  # add: -DPACKETVER=20211103

cmake --build build --parallel 1
cmake --install build
chmod a+x athena-start
./athena-start start
```

---

## Client notes

1. Use a client whose date matches your `PACKETVER`.
2. Patch with NEMO (or similar) for your private server.
3. Point `clientinfo.xml` / `sclientinfo.xml` at `YOUR.PUBLIC.IP` port `6900`.

Create a player account in MariaDB (example plaintext password):

```sql
INSERT INTO `login` (`userid`, `user_pass`, `sex`, `email`, `group_id`)
VALUES ('test', 'test', 'M', 'test@localhost', 0);
```

GM account: set `group_id` high (see `conf/groups.conf`, often `99`).

---

## Useful links

- [Hercules Building wiki](https://github.com/HerculesWS/Hercules/wiki/Building)
- [Hercules Installation wiki](https://github.com/HerculesWS/Hercules/wiki/Installation)
- [Official docs (Debian)](https://docs.herc.ws/setup/installation/installation-debian/)
- Forum / Discord: [herc.ws](https://herc.ws)

## Script options

| Variable | Default | Meaning |
|----------|---------|---------|
| `SERVER_IP` | `127.0.0.1` | IP written into char/map configs |
| `DB_NAME` / `DB_USER` / `DB_PASS` | `hercules` / random pass | MariaDB credentials |
| `HERC_USER` | `hercuser` | Linux user that owns the files |
| `HERC_BRANCH` | `stable` | Git branch or tag |
| `ENABLE_RENEWAL` | `ON` | Renewal (`ON`) or pre-renewal (`OFF`) |
| `PACKETVER` | empty | Client packet date, e.g. `20211103` |
| `SWAP_GB` | `2` | Swap size created if missing |
| `SKIP_BUILD` / `SKIP_DB` | `0` | Skip compile or DB import |
