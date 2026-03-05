#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║         DNSTT Unbound Resolver Manager                      ║
# ║         Fast • Secure • TXT-Optimized DNS Tunnel            ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Colors & Styles ───────────────────────────────────────────
R='\033[0;31m'   G='\033[0;32m'   Y='\033[1;33m'
B='\033[0;34m'   C='\033[0;36m'   M='\033[0;35m'
W='\033[1;37m'   DIM='\033[2m'    BOLD='\033[1m'
NC='\033[0m'     BG_B='\033[44m'  BG_G='\033[42m'

# ─── Config ────────────────────────────────────────────────────
UNBOUND_CONF="/etc/unbound/unbound.conf"
BACKUP_CONF="/etc/unbound/unbound.conf.dnstt-backup"
LOG_FILE="/var/log/dnstt-resolver.log"
SCRIPT_MARKER="/etc/unbound/.dnstt-managed"

# ─── Helpers ───────────────────────────────────────────────────
log()       { echo -e "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true; }
die()       { echo -e "\n${R}✗ ERROR:${NC} $*\n" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"; }

# ─── UI Components ─────────────────────────────────────────────
clear_screen() { printf '\033[2J\033[H'; }

banner() {
    clear_screen
    echo -e "${C}${BOLD}"
    echo "  ██████╗ ███╗   ██╗███████╗████████╗████████╗"
    echo "  ██╔══██╗████╗  ██║██╔════╝╚══██╔══╝╚══██╔══╝"
    echo "  ██║  ██║██╔██╗ ██║███████╗   ██║      ██║   "
    echo "  ██║  ██║██║╚██╗██║╚════██║   ██║      ██║   "
    echo "  ██████╔╝██║ ╚████║███████║   ██║      ██║   "
    echo "  ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝      ╚═╝  "
    echo -e "${NC}${DIM}           Unbound Resolver · DNSTT Optimized${NC}"
    echo -e "${DIM}  ─────────────────────────────────────────────${NC}"
}

section() {
    echo -e "\n${BG_B}${W}  $1  ${NC}"
}

status_line() {
    local label="$1" value="$2" color="${3:-$W}"
    printf "  ${DIM}%-22s${NC} ${color}%s${NC}\n" "$label" "$value"
}

ok()   { echo -e "  ${G}✔${NC} $*"; }
info() { echo -e "  ${C}ℹ${NC} $*"; }
warn() { echo -e "  ${Y}⚠${NC} $*"; }
step() { echo -e "\n  ${M}▸${NC} ${BOLD}$*${NC}"; }

# ─── Spinner: stdin redirected so apt can't steal the terminal ─
run_spinner() {
    local msg="$1"
    shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 rc=0

    # </dev/null is critical — prevents background process from
    # consuming stdin and kicking us out of the script
    "$@" </dev/null >> "$LOG_FILE" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${C}${frames[$((i % ${#frames[@]}))]}${NC}  %s" "$msg"
        sleep 0.1
        ((i++)) || true
    done

    wait "$pid" && rc=0 || rc=$?
    printf "\r%-60s\r" ""
    return $rc
}

confirm() {
    local prompt="${1:-Continue?}"
    echo -e "\n  ${Y}?${NC} ${BOLD}${prompt}${NC} [y/N]"
    printf "  → "
    local ans
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

press_enter() {
    echo -e "\n  ${DIM}Press Enter to continue...${NC}"
    read -r
}

# ─── Status Dashboard ──────────────────────────────────────────
show_dashboard() {
    banner
    section "⚡ SYSTEM STATUS"

    local svc_status svc_color
    if systemctl is-active --quiet unbound 2>/dev/null; then
        svc_status="● RUNNING" svc_color="$G"
    else
        svc_status="○ STOPPED" svc_color="$R"
    fi

    local managed_status managed_color
    if [[ -f "$SCRIPT_MARKER" ]]; then
        managed_status="YES (this script)" managed_color="$G"
    else
        managed_status="NOT managed here" managed_color="$Y"
    fi

    local boot_status boot_color
    if systemctl is-enabled --quiet unbound 2>/dev/null; then
        boot_status="Enabled on boot" boot_color="$G"
    else
        boot_status="Not enabled" boot_color="$Y"
    fi

    local fw_status fw_color
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "53.*ALLOW"; then
        fw_status="UFW: Port 53 allowed" fw_color="$G"
    elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        fw_status="UFW active (check 53)" fw_color="$Y"
    else
        fw_status="UFW inactive / N/A" fw_color="$DIM"
    fi

    local port_status port_color
    if ss -ulnp 2>/dev/null | grep -q ':53 ' || ss -tlnp 2>/dev/null | grep -q ':53 '; then
        port_status="Port 53 OPEN" port_color="$G"
    else
        port_status="Port 53 closed" port_color="$R"
    fi

    local dns_status dns_color
    if dig @127.0.0.1 google.com TXT +short +timeout=2 &>/dev/null; then
        dns_status="TXT lookup OK ✔" dns_color="$G"
    else
        dns_status="TXT lookup failed" dns_color="$R"
    fi

    echo ""
    status_line "Unbound Service:" "$svc_status" "$svc_color"
    status_line "Boot Autostart:" "$boot_status" "$boot_color"
    status_line "Managed by script:" "$managed_status" "$managed_color"
    status_line "Firewall:" "$fw_status" "$fw_color"
    status_line "Network:" "$port_status" "$port_color"
    status_line "DNS TXT Test:" "$dns_status" "$dns_color"
    status_line "Server IP:" "$(hostname -I | awk '{print $1}')" "$C"
    status_line "Config file:" "$UNBOUND_CONF" "$DIM"

    section "📊 LIVE STATS"
    echo ""

    if systemctl is-active --quiet unbound 2>/dev/null; then
        local uptime_str
        uptime_str=$(systemctl show unbound --property=ActiveEnterTimestamp \
            | cut -d= -f2 | xargs -I{} date -d "{}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
        status_line "Active since:" "$uptime_str" "$C"

        local mem
        mem=$(ps -o rss= -p "$(pidof unbound 2>/dev/null | awk '{print $1}')" 2>/dev/null \
            | awk '{printf "%.1f MB", $1/1024}' || echo "N/A")
        status_line "Memory usage:" "$mem" "$C"
    else
        status_line "Uptime:" "N/A (not running)" "$DIM"
    fi

    if [[ -f "$UNBOUND_CONF" ]]; then
        local conf_lines
        conf_lines=$(grep -c . "$UNBOUND_CONF" 2>/dev/null || echo "0")
        status_line "Config lines:" "$conf_lines" "$DIM"
    fi

    echo -e "\n  ${DIM}Last refresh: $(date '+%H:%M:%S')${NC}"
}

# ─── Firewall Setup ────────────────────────────────────────────
setup_firewall() {
    step "Configuring firewall (UFW)..."

    if ! command -v ufw &>/dev/null; then
        info "UFW not found — installing..."
        if run_spinner "Installing ufw..." apt-get install -y ufw; then
            ok "UFW installed"
        else
            warn "UFW install failed — skipping firewall config"
            return
        fi
    fi

    # Always allow SSH first — prevents lockout
    ufw allow ssh >/dev/null 2>&1 || true
    ok "SSH access preserved (port 22)"

    # Allow DNS on both protocols
    ufw allow 53/udp >/dev/null 2>&1
    ufw allow 53/tcp >/dev/null 2>&1
    ok "Port 53 UDP/TCP opened"

    # Enable if not already active
    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "y" | ufw enable >/dev/null 2>&1 || true
        ok "UFW enabled"
    else
        ok "UFW already active — rules added"
    fi

    # Print the new 53 rules
    local rules
    rules=$(ufw status 2>/dev/null | grep "\b53\b" | sed 's/^/    /')
    [[ -n "$rules" ]] && echo -e "${DIM}${rules}${NC}"
}

# ─── Installation ──────────────────────────────────────────────
do_install() {
    banner
    section "🚀 INSTALLING DNSTT-OPTIMIZED UNBOUND RESOLVER"
    echo ""

    need_root

    if [[ -f "$SCRIPT_MARKER" ]]; then
        warn "Already installed by this script."
        if ! confirm "Re-install / overwrite config?"; then
            press_enter
            return
        fi
    fi

    step "Updating package lists..."
    if run_spinner "Updating apt..." apt-get update -qq; then
        ok "Package lists updated"
    else
        die "apt-get update failed — check $LOG_FILE"
    fi

    step "Installing Unbound + dnsutils..."
    if run_spinner "Installing packages..." apt-get install -y unbound dnsutils; then
        ok "Unbound + dnsutils installed"
    else
        die "Package install failed — check $LOG_FILE"
    fi

    step "Backing up existing config..."
    if [[ -f "$UNBOUND_CONF" ]]; then
        cp "$UNBOUND_CONF" "$BACKUP_CONF"
        ok "Backup saved → $BACKUP_CONF"
    else
        info "No existing config to back up"
    fi

    step "Writing optimized DNSTT resolver config..."
    mkdir -p /etc/unbound
    cat > "$UNBOUND_CONF" <<'UNBOUNDEOF'
# ── Unbound: DNSTT-Optimized Resolver ──────────────────────────
server:
    # ── Network ──────────────────────────────────────────────
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes

    # ── Access Control ───────────────────────────────────────
    access-control: 0.0.0.0/0 allow
    access-control: ::0/0 allow

    # ── Privacy & Security ───────────────────────────────────
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-below-nxdomain: yes
    harden-referral-path: yes
    use-caps-for-id: yes
    val-clean-additional: yes

    # ── TXT Record / DNSTT Optimization ─────────────────────
    msg-buffer-size: 65552
    edns-buffer-size: 4096
    max-udp-size: 4096

    # ── Performance Tuning ───────────────────────────────────
    num-threads: 4
    so-rcvbuf: 4m
    so-sndbuf: 4m
    msg-cache-size: 64m
    rrset-cache-size: 128m
    prefetch: yes
    prefetch-key: yes
    cache-min-ttl: 10
    cache-max-ttl: 86400
    infra-host-ttl: 60

    # ── Logging ──────────────────────────────────────────────
    verbosity: 0
    use-syslog: yes
    log-queries: no
UNBOUNDEOF
    ok "Config written → $UNBOUND_CONF"

    setup_firewall

    step "Creating managed marker..."
    echo "installed=$(date '+%Y-%m-%d %H:%M:%S')" > "$SCRIPT_MARKER"
    echo "version=1.0" >> "$SCRIPT_MARKER"
    ok "Marker created"

    step "Enabling Unbound on boot..."
    systemctl enable unbound >/dev/null 2>&1
    ok "Boot autostart enabled"

    step "Starting Unbound..."
    systemctl restart unbound
    sleep 1
    if systemctl is-active --quiet unbound; then
        ok "Unbound is running"
    else
        warn "Unbound may have failed — check: journalctl -u unbound -n 20"
    fi

    step "Verifying TXT resolution..."
    sleep 1
    if dig @127.0.0.1 google.com TXT +short +timeout=4 &>/dev/null; then
        ok "TXT query test: ${G}PASSED${NC}"
    else
        warn "TXT query test failed — check: journalctl -u unbound -n 20"
    fi

    echo ""
    echo -e "  ${BG_G}${W}  ✔ INSTALLATION COMPLETE  ${NC}"
    local ip
    ip=$(hostname -I | awk '{print $1}')
    echo -e "\n  ${DIM}Point your DNSTT client at:${NC} ${C}${BOLD}${ip}${NC}"
    echo -e "  ${DIM}Log file:${NC} $LOG_FILE"
    press_enter
}

# ─── Removal ───────────────────────────────────────────────────
do_remove() {
    banner
    section "🗑  REMOVE DNSTT RESOLVER"
    echo ""

    need_root

    if [[ ! -f "$SCRIPT_MARKER" ]]; then
        warn "This installation was not managed by this script."
        if ! confirm "Remove Unbound anyway (full purge)?"; then
            press_enter
            return
        fi
    fi

    echo -e "\n  ${R}${BOLD}This will:${NC}"
    echo -e "  ${R}•${NC} Stop and disable Unbound"
    echo -e "  ${R}•${NC} Purge the unbound package"
    echo -e "  ${R}•${NC} Remove all configs in /etc/unbound/"
    echo -e "  ${R}•${NC} Remove UFW port 53 rules"
    echo ""

    if ! confirm "Confirm FULL removal?"; then
        info "Removal cancelled."
        press_enter
        return
    fi

    step "Stopping Unbound..."
    systemctl stop unbound 2>/dev/null && ok "Stopped" || warn "Was not running"

    step "Disabling autostart..."
    systemctl disable unbound 2>/dev/null && ok "Boot autostart removed" || true

    step "Purging package..."
    if run_spinner "Purging unbound..." apt-get purge -y unbound unbound-anchor; then
        ok "Package purged"
    else
        warn "Purge had errors — check $LOG_FILE"
    fi

    step "Cleaning config directory..."
    rm -rf /etc/unbound/
    ok "/etc/unbound/ removed"

    step "Removing UFW port 53 rules..."
    if command -v ufw &>/dev/null; then
        ufw delete allow 53/udp >/dev/null 2>&1 && ok "UDP 53 rule removed" || info "No UDP 53 rule to remove"
        ufw delete allow 53/tcp >/dev/null 2>&1 && ok "TCP 53 rule removed" || info "No TCP 53 rule to remove"
    else
        info "UFW not installed — nothing to clean"
    fi

    step "Cleaning up unused packages..."
    run_spinner "Autoremove..." apt-get autoremove -y || true
    ok "Cleanup done"

    echo ""
    echo -e "  ${BG_B}${W}  ✔ REMOVAL COMPLETE  ${NC}"
    echo -e "  ${DIM}Log preserved at:${NC} $LOG_FILE"
    press_enter
}

# ─── Quick Actions ─────────────────────────────────────────────
do_test() {
    banner
    section "🔍 DNS TXT RESOLUTION TEST"
    echo ""

    local targets=("google.com" "cloudflare.com" "github.com")

    for domain in "${targets[@]}"; do
        printf "  ${C}%-20s${NC}" "$domain TXT"
        result=$(dig @127.0.0.1 "$domain" TXT +short +timeout=4 2>/dev/null | head -1)
        if [[ -n "$result" ]]; then
            echo -e "${G}✔${NC} ${DIM}${result:0:60}...${NC}"
        else
            echo -e "${R}✗ No response${NC}"
        fi
    done

    echo ""
    step "Raw dig output (google.com TXT @127.0.0.1):"
    echo ""
    dig @127.0.0.1 google.com TXT +noall +answer 2>/dev/null \
        | sed 's/^/  /' | head -20 \
        || warn "dig not available — install dnsutils"

    press_enter
}

do_logs() {
    banner
    section "📋 UNBOUND LIVE LOGS"
    echo -e "  ${DIM}(Press Ctrl+C to exit)${NC}\n"
    journalctl -u unbound -f --no-pager -n 40 2>/dev/null \
        | sed "s/unbound\[/${C}unbound[${NC}/g" \
        || warn "journalctl not available"
    press_enter
}

do_restart() {
    need_root
    step "Restarting Unbound..."
    systemctl restart unbound && ok "Restarted successfully" || warn "Restart failed — check journalctl -u unbound"
    sleep 1
}

do_config_view() {
    banner
    section "📄 CURRENT CONFIGURATION"
    echo ""
    if [[ -f "$UNBOUND_CONF" ]]; then
        grep -n '' "$UNBOUND_CONF" \
            | grep -v '^\s*[0-9]*:\s*#' \
            | grep -v '^\s*[0-9]*:\s*$' \
            | sed "s/^\([0-9]*\):/  ${DIM}\1${NC}\t/" \
            | head -80
    else
        warn "No config found at $UNBOUND_CONF"
    fi
    press_enter
}

# ─── Main Menu ─────────────────────────────────────────────────
main_menu() {
    while true; do
        show_dashboard
        echo ""
        echo -e "  ${BOLD}${W}MENU${NC}"
        echo -e "  ${DIM}──────────────────────────${NC}"
        echo -e "  ${G}1${NC}  Install / Configure resolver"
        echo -e "  ${C}2${NC}  Show live status (refresh)"
        echo -e "  ${Y}3${NC}  Test TXT resolution"
        echo -e "  ${B}4${NC}  View current config"
        echo -e "  ${M}5${NC}  View live logs"
        echo -e "  ${C}6${NC}  Restart Unbound"
        echo -e "  ${R}7${NC}  REMOVE resolver (full uninstall)"
        echo -e "  ${DIM}0${NC}  Exit"
        echo -e "\n  ${DIM}──────────────────────────${NC}"
        printf "  ${W}Choose${NC} [0-7]: "

        local choice
        read -r choice

        case "$choice" in
            1) do_install     ;;
            2) :              ;;
            3) do_test        ;;
            4) do_config_view ;;
            5) do_logs        ;;
            6) do_restart     ;;
            7) do_remove      ;;
            0) echo -e "\n  ${DIM}Goodbye.${NC}\n"; exit 0 ;;
            *) warn "Invalid option" ; sleep 0.5 ;;
        esac
    done
}

# ─── Entry Point ───────────────────────────────────────────────
touch "$LOG_FILE" 2>/dev/null || true
main_menu
