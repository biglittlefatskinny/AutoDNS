# AutoDNS 🛰️
> One-command Unbound DNS resolver — optimized for [DNSTT](https://www.bamsoftware.com/software/dnstt/) tunneling, with a terminal dashboard and clean uninstall.

---

## ⚡ Quick Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/biglittlefatskinny/AutoDNS/main/dnstt-resolver.sh -o dnstt-resolver.sh && chmod +x dnstt-resolver.sh && sudo ./dnstt-resolver.sh
```

---

## 📦 Clone & Run

```bash
git clone https://github.com/biglittlefatskinny/AutoDNS.git
cd AutoDNS
chmod +x dnstt-resolver.sh
sudo ./dnstt-resolver.sh
```

---

## 📋 What It Does

AutoDNS installs and configures **Unbound** as a high-performance, open DNS resolver tuned specifically for DNSTT DNS tunneling. It handles large `TXT` record payloads reliably — which standard resolvers often drop or truncate.

Once launched, it drops you into an interactive terminal dashboard:

```
  ██████╗ ███╗   ██╗███████╗████████╗████████╗
  ██╔══██╗████╗  ██║██╔════╝╚══██╔══╝╚══██╔══╝
  ██║  ██║██╔██╗ ██║███████╗   ██║      ██║
  ██║  ██║██║╚██╗██║╚════██║   ██║      ██║
  ██████╔╝██║ ╚████║███████║   ██║      ██║
  ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝      ╚═╝
           Unbound Resolver · DNSTT Optimized

  MENU
  ──────────────────────────
  1  Install / Configure resolver
  2  Show live status (refresh)
  3  Test TXT resolution
  4  View current config
  5  View live logs
  6  Restart Unbound
  7  REMOVE resolver (full uninstall)
  0  Exit
```

---

## 🎛️ Menu Options

| Option | Description |
|--------|-------------|
| `1` | Install Unbound, write optimized config, open firewall ports, enable on boot |
| `2` | Refresh live dashboard (service status, firewall, port check, TXT test) |
| `3` | Run TXT lookup tests against google.com, cloudflare.com, github.com |
| `4` | View the current `/etc/unbound/unbound.conf` |
| `5` | Stream live Unbound logs (`Ctrl+C` to exit) |
| `6` | Restart the Unbound service |
| `7` | **Full removal** — stops service, purges package, wipes config, removes firewall rules |

---

## 🔧 What Gets Configured

The script writes an optimized `/etc/unbound/unbound.conf` with:

| Setting | Value | Why |
|---------|-------|-----|
| `msg-buffer-size` | `65552` | Handles oversized DNSTT TXT payloads |
| `edns-buffer-size` | `4096` | Max EDNS buffer for large records |
| `max-udp-size` | `4096` | Prevents UDP truncation of TXT data |
| `num-threads` | `4` | Parallel query handling |
| `msg-cache-size` | `64m` | Fast repeated lookups |
| `rrset-cache-size` | `128m` | Large record set caching |
| `access-control` | `0.0.0.0/0 allow` | Open to tunnel clients |
| `hide-identity` | `yes` | Privacy |
| `harden-dnssec-stripped` | `yes` | Security |
| `prefetch` | `yes` | Warm cache = lower latency |

The original config (if any) is backed up to `/etc/unbound/unbound.conf.dnstt-backup` before being overwritten.

---

## 🔥 Firewall

The install step automatically handles UFW for you:

- Installs UFW if not present
- Preserves SSH access (port 22) before making any changes
- Opens **port 53 UDP + TCP** for DNS tunnel traffic
- Enables UFW if it wasn't already active
- Removal (option `7`) automatically deletes the port 53 rules

---

## 🗑️ Uninstall

From the dashboard, press `7` and confirm. This will:
- Stop and disable the Unbound service
- Purge the `unbound` package and all configs
- Remove `/etc/unbound/` entirely
- Remove UFW port 53 rules
- Run `apt autoremove` to clean up

Or manually:
```bash
sudo systemctl stop unbound
sudo apt purge -y unbound
sudo rm -rf /etc/unbound/
sudo ufw delete allow 53/udp
sudo ufw delete allow 53/tcp
```

---

## 📋 Requirements

- Ubuntu / Debian-based system
- `root` or `sudo` access
- Internet access (to install packages)
- `dnsutils` (auto-installed — provides `dig` for tests)

---

## 🔗 Related

- [DNSTT — DNS Tunnel Toolkit](https://www.bamsoftware.com/software/dnstt/)
- [Unbound DNS Documentation](https://unbound.docs.nlnetlabs.nl/)

---

## 📄 License

MIT — free to use, modify, and distribute.
