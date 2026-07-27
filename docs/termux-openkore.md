# OpenKore on Termux (host #3)

Ranarokx bot host is **Termux**, talking to Hercules on **Linux #1**.

| Do | Don’t |
|----|--------|
| Use Linux **public IP** in `servers.txt` | Use `127.0.0.1` / `forceMapIP 127.0.0.1` |
| `serverType kRO_RagexeRE_2018_11_21` | Assume a second Linux “OpenKore VPS” |
| Keep Termux session healthy (force-stop if shell goes silent) | Install OpenKore on Windows #2 |

Game ports **6900 / 6121 / 5121** must be reachable from your phone.

---

## 1) Packages

```bash
pkg update && pkg upgrade -y
pkg install -y git clang make python perl openssl libcurl readline ncurses libandroid-spawn
```

## 2) Clone

```bash
cd ~
git clone --depth 1 https://github.com/OpenKore/openkore.git
cd ~/openkore
```

## 3) Add server block

Append to `tables/servers.txt` (replace `YOUR.PUBLIC.IP`):

```
[Ragnax]
ip YOUR.PUBLIC.IP
port 6900
master_version 1
version 55
serverType kRO_RagexeRE_2018_11_21
serverEncoding Western
charBlockSize 155
addTableFolders translated/kRO_english;kRO
```

## 4) Login config

`control/config.txt` uses bare keys (no values). Set:

```bash
cd ~/openkore
sed -i 's/^master$/master Ragnax/' control/config.txt
sed -i 's/^username$/username admin/' control/config.txt
sed -i 's/^password$/password admin123/' control/config.txt
# XKore should already be 0
grep -nE '^(master|username|password|XKore) ' control/config.txt
```

## 5) Hercules recvpackets

```bash
cd ~/openkore && python3 - <<'PY'
from pathlib import Path
path = Path("tables/kRO/recvpackets.txt")
begin = "# >>> RANAROKX_PACKETS_BEGIN\n"
end = "# <<< RANAROKX_PACKETS_END\n"
block = begin + "\n".join([
    "0AC4 0", "0AE3 0", "082D 0", "08B9 12", "099D 0", "09A0 4",
    "0AC5 156", "0AC7 156", "09E7 3", "0B18 4", "0ADE 6", "0A23 -1",
    "0ADC 6", "0ADD 24", "0AE0 30", "0AE1 28",
]) + "\n" + end
text = path.read_text()
if begin in text and end in text:
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    text = pre + block + post
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + block
path.write_text(text)
print("recvpackets patched")
PY
```

## 6) UTF-8 quests.txt

```bash
cd ~/openkore && python3 - <<'PY'
from pathlib import Path
q = Path("tables/translated/kRO_english/quests.txt")
data = q.read_bytes()
try:
    data.decode("utf-8")
    print("already utf-8")
except UnicodeDecodeError:
    q.write_text(data.decode("latin-1"), encoding="utf-8")
    print("quests utf8 ok")
PY
```

## 7) Termux build fixes

Patch `SConstruct` for Termux paths + C++ flags, add hash shim, then build:

```bash
cd ~/openkore && python3 - <<'PY'
from pathlib import Path
import re

p = Path("SConstruct")
text = p.read_text()
text = text.replace(
    "EXTRA_INCLUDE_DIRECTORIES = []",
    "EXTRA_INCLUDE_DIRECTORIES = ['/data/data/com.termux/files/usr/include']",
    1,
)
text = text.replace(
    "EXTRA_LIBRARY_DIRECTORIES = []",
    "EXTRA_LIBRARY_DIRECTORIES = ['/data/data/com.termux/files/usr/lib']",
    1,
)
text = text.replace(
    "EXTRA_COMPILER_FLAGS = ['-Wall', '-O3', '-pipe']",
    "EXTRA_COMPILER_FLAGS = ['-Wall', '-O3', '-pipe', '-Wno-register', '-std=gnu++14']",
    1,
)
if "ENV = os.environ" not in text:
    text = text.replace(
        "env = Environment()\n",
        "env = Environment(ENV = os.environ)\n"
        "env['CPPPATH'] = EXTRA_INCLUDE_DIRECTORIES\n"
        "env['LIBPATH'] = EXTRA_LIBRARY_DIRECTORIES\n",
        1,
    )
p.write_text(text)

shim = Path("src/auto/XSTools/utils/hash_fun_shim.h")
shim.write_text(r'''#ifndef OPENKORE_HASH_FUN_SHIM_H
#define OPENKORE_HASH_FUN_SHIM_H
#include <cstddef>
#include <string>
namespace __gnu_cxx {
template <typename T>
struct hash {
  std::size_t operator()(const T& v) const { return std::hash<T>()(v); }
};
template <>
struct hash<const char*> {
  std::size_t operator()(const char* s) const {
    std::size_t h = 0;
    if (!s) return 0;
    for (; *s; ++s) h = 5 * h + static_cast<unsigned char>(*s);
    return h;
  }
};
template <>
struct hash<char*> {
  std::size_t operator()(char* s) const {
    return hash<const char*>()(s);
  }
};
}
#endif
''')
sc = Path("src/auto/XSTools/utils/sparseconfig.h")
text = sc.read_text()
text = re.sub(
    r'#define HASH_FUN_H <(?:ext|backward)/hash_fun\.h>',
    '#define HASH_FUN_H "hash_fun_shim.h"',
    text,
)
sc.write_text(text)
print("Termux build patches applied")
PY

rm -rf .sconsign.dblite config.log .sconf_temp
python src/scons-local-3.1.2/scons.py --config=force
# if `python` missing: python3 src/scons-local-3.1.2/scons.py --config=force
```

## 8) Run (Android needs LD_PRELOAD)

```bash
cd ~/openkore
export LD_PRELOAD=/data/data/com.termux/files/usr/lib/libperl.so
perl openkore.pl
```

If login times out on `YOUR.PUBLIC.IP:6900`, fix host/NAT port forwards on Linux #1 first.

---

## Optional: OpenKore on Linux #1

Only if you want a bot on the game box itself:

```bash
sudo SERVER_IP=127.0.0.1 bash scripts/install-openkore-linux.sh
```

That path uses `forceMapIP 127.0.0.1`. Termux must **not** copy that setting.
