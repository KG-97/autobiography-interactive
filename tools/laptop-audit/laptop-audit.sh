#!/usr/bin/env bash
# laptop-audit.sh - read-only health, performance and security audit
#                   for macOS and Linux laptops.
#
# Nothing on the machine is modified. The only file written is the report.
#
# Usage:
#   bash laptop-audit.sh            # standard audit
#   bash laptop-audit.sh --deep     # also scan $HOME for large + duplicate files
#   bash laptop-audit.sh --out DIR  # report directory (default: $HOME)

set -o pipefail

DEEP=0
OUTDIR="$HOME"
LARGE_MB=250

while [ $# -gt 0 ]; do
  case "$1" in
    --deep) DEEP=1 ;;
    --out) OUTDIR="$2"; shift ;;
    --large-mb) LARGE_MB="$2"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

OS="$(uname -s)"
HOSTNAME_S="$(hostname 2>/dev/null | cut -d. -f1)"
STAMP="$(date +%Y-%m-%d_%H%M)"
REPORT="$OUTDIR/laptop-audit_${HOSTNAME_S}_${STAMP}.md"
TMPDIR_A="$(mktemp -d)"
FINDINGS="$TMPDIR_A/findings"
BODY="$TMPDIR_A/body"
: > "$FINDINGS"; : > "$BODY"
trap 'rm -rf "$TMPDIR_A"' EXIT

C_CYAN=$'\033[36m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_GRY=$'\033[90m'; C_OFF=$'\033[0m'

section() { printf '\n%s== %s%s\n' "$C_CYAN" "$1" "$C_OFF"; printf '\n## %s\n\n' "$1" >> "$BODY"; }
say()     { printf '   %s\n' "$1"; printf -- '- %s\n' "$1" >> "$BODY"; }
raw()     { printf '\n```\n%s\n```\n' "$1" >> "$BODY"; }
finding() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FINDINGS"; }
have()    { command -v "$1" >/dev/null 2>&1; }
human()   { # bytes -> human
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB TB",u," "); i=1;
    while (b>=1024 && i<5){b/=1024;i++}
    printf (i==1 ? "%.0f %s" : "%.1f %s"), b, u[i]
  }'
}

printf '\n%s LAPTOP AUDIT %s  %s on %s | deep=%s\n' "$C_CYAN" "$C_OFF" "$OS" "$HOSTNAME_S" "$DEEP"
printf '%s Read-only. Nothing on this machine is modified.%s\n' "$C_GRY" "$C_OFF"

# ------------------------------------------------------------- 1. system ---
section "System identity"

if [ "$OS" = "Darwin" ]; then
  say "macOS $(sw_vers -productVersion 2>/dev/null) build $(sw_vers -buildVersion 2>/dev/null)"
  say "Model: $(sysctl -n hw.model 2>/dev/null)"
  BOOT_EPOCH=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\).*/\1/p')
  [ -n "$BOOT_EPOCH" ] && say "Uptime: $(( ( $(date +%s) - BOOT_EPOCH ) / 86400 )) days"
else
  if [ -r /etc/os-release ]; then . /etc/os-release; say "${PRETTY_NAME:-unknown Linux}"; fi
  say "Kernel: $(uname -r)"
  have hostnamectl && say "Chassis: $(hostnamectl chassis 2>/dev/null || echo unknown)"
  [ -r /proc/uptime ] && say "Uptime: $(awk '{printf "%.1f", $1/86400}' /proc/uptime) days"
fi
say "User: $(id -un)  Shell: ${SHELL:-unknown}"

UPDAYS=0
if [ "$OS" = "Darwin" ] && [ -n "$BOOT_EPOCH" ]; then
  UPDAYS=$(( ( $(date +%s) - BOOT_EPOCH ) / 86400 ))
elif [ -r /proc/uptime ]; then
  UPDAYS=$(awk '{printf "%d", $1/86400}' /proc/uptime)
fi
[ "$UPDAYS" -gt 14 ] 2>/dev/null && finding LOW System "Long uptime" \
  "Running $UPDAYS days without a restart." "Restart to apply pending kernel/security updates."

# ----------------------------------------------------------- 2. hardware ---
section "Hardware"

if [ "$OS" = "Darwin" ]; then
  say "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  say "Cores: $(sysctl -n hw.ncpu 2>/dev/null)"
  RAM_B=$(sysctl -n hw.memsize 2>/dev/null)
  say "RAM: $(human "${RAM_B:-0}")"
  PRESSURE=$(memory_pressure 2>/dev/null | tail -1)
  [ -n "$PRESSURE" ] && say "$PRESSURE"
else
  have lscpu && say "CPU: $(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -1)"
  say "Cores: $(nproc 2>/dev/null)"
  if [ -r /proc/meminfo ]; then
    RAM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    AVAIL_KB=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    RAM_B=$((RAM_KB * 1024))
    say "RAM: $(human "$RAM_B") total, $(human $((AVAIL_KB * 1024))) available"
    USED_PCT=$(awk -v t="$RAM_KB" -v a="$AVAIL_KB" 'BEGIN{printf "%.0f", (1-a/t)*100}')
    say "Memory in use: ${USED_PCT}%"
    [ "$USED_PCT" -ge 90 ] 2>/dev/null && finding HIGH Hardware "Memory pressure" \
      "${USED_PCT}% of RAM in use." "Check the top-memory processes below for a leak."
  fi
fi
if [ -n "${RAM_B:-}" ] && [ "$RAM_B" -lt 8589934592 ] 2>/dev/null; then
  finding MEDIUM Hardware "Low installed RAM" "Only $(human "$RAM_B") installed." \
    "Under 8 GB is tight for a browser plus dev tooling."
fi

# ------------------------------------------------------------ 3. battery ---
section "Battery"

if [ "$OS" = "Darwin" ]; then
  BATT="$(system_profiler SPPowerDataType 2>/dev/null)"
  if [ -n "$BATT" ]; then
    CYCLES=$(printf '%s' "$BATT" | sed -n 's/.*Cycle Count: *//p' | head -1)
    COND=$(printf '%s' "$BATT" | sed -n 's/.*Condition: *//p' | head -1)
    MAXCAP=$(printf '%s' "$BATT" | sed -n 's/.*Maximum Capacity: *//p' | head -1)
    say "Condition: ${COND:-unknown}  Cycles: ${CYCLES:-unknown}  Max capacity: ${MAXCAP:-unknown}"
    case "$COND" in
      ""|Normal) : ;;
      *) finding HIGH Battery "Battery condition: $COND" \
           "macOS reports the battery as '$COND'." "Book a battery replacement." ;;
    esac
    HP=$(printf '%s' "${MAXCAP:-}" | tr -dc '0-9')
    if [ -n "$HP" ] && [ "$HP" -lt 80 ] 2>/dev/null; then
      finding MEDIUM Battery "Battery wear" "Maximum capacity is ${HP}% of design." \
        "Normal with age; enable Optimized Charging, plan a replacement under 60%."
    fi
  else
    say "No battery data (desktop or restricted)."
  fi
else
  BATDIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
  if [ -n "$BATDIR" ]; then
    read_f() { [ -r "$BATDIR/$1" ] && cat "$BATDIR/$1" 2>/dev/null; }
    FULL=$(read_f energy_full); DESIGN=$(read_f energy_full_design)
    [ -z "$FULL" ] && FULL=$(read_f charge_full)
    [ -z "$DESIGN" ] && DESIGN=$(read_f charge_full_design)
    CAP=$(read_f capacity); CYC=$(read_f cycle_count)
    say "Charge: ${CAP:-?}%  Cycles: ${CYC:-unknown}"
    if [ -n "$FULL" ] && [ -n "$DESIGN" ] && [ "$DESIGN" -gt 0 ] 2>/dev/null; then
      HP=$(awk -v f="$FULL" -v d="$DESIGN" 'BEGIN{printf "%.0f", f/d*100}')
      say "Health: ${HP}% of design capacity"
      if [ "$HP" -lt 60 ] 2>/dev/null; then
        finding HIGH Battery "Battery badly degraded" "Full charge is ${HP}% of design capacity." \
          "Expect roughly half the original runtime; replacement is the only fix."
      elif [ "$HP" -lt 80 ] 2>/dev/null; then
        finding MEDIUM Battery "Battery wear" "Full charge is ${HP}% of design capacity." \
          "Normal with age; set a charge threshold if your firmware supports one."
      fi
    fi
  else
    say "No battery detected."
  fi
fi

# ------------------------------------------------------------ 4. storage ---
section "Storage"

DF_OUT="$(df -h 2>/dev/null | grep -E '^/dev|^map|^/System' | head -20)"
raw "$DF_OUT"
printf '%s\n' "$DF_OUT" | while read -r dev size used avail pct mount; do
  [ -z "$pct" ] && continue
  printf '   %-22s %5s free of %-6s (%s used)  %s\n' "$dev" "$avail" "$size" "$pct" "$mount"
done

ROOT_PCT=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
if [ -n "$ROOT_PCT" ]; then
  FREE_PCT=$((100 - ROOT_PCT))
  if [ "$FREE_PCT" -lt 5 ]; then
    finding CRITICAL Storage "Root filesystem nearly full" "${FREE_PCT}% free on /." \
      "The OS needs headroom for updates and swap. Clear space now."
  elif [ "$FREE_PCT" -lt 15 ]; then
    finding HIGH Storage "Root filesystem low on space" "${FREE_PCT}% free on /." \
      "Clear caches and the largest home directories listed below."
  fi
fi

say "Largest directories in \$HOME (top level):"
DU_OUT="$(du -sh "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -rh | head -15)"
raw "$DU_OUT"
printf '%s\n' "$DU_OUT" | head -10 | sed 's/^/   /'

for d in "$HOME/Downloads" "$HOME/Desktop"; do
  [ -d "$d" ] || continue
  BYTES=$(du -sk "$d" 2>/dev/null | awk '{print $1*1024}')
  [ -z "$BYTES" ] && continue
  if [ "$BYTES" -gt 21474836480 ] 2>/dev/null; then
    finding LOW Storage "$(basename "$d") is large" "$(human "$BYTES") in $d." \
      "Usually the cheapest space to reclaim."
  fi
done

CACHE_DIRS="$HOME/Library/Caches $HOME/.cache"
for c in $CACHE_DIRS; do
  [ -d "$c" ] || continue
  CB=$(du -sk "$c" 2>/dev/null | awk '{print $1*1024}')
  say "Cache $c: $(human "${CB:-0}")"
  [ -n "$CB" ] && [ "$CB" -gt 10737418240 ] 2>/dev/null && finding MEDIUM Storage "Large cache directory" \
    "$c holds $(human "$CB")." "Safe to clear; applications rebuild it."
done

if have smartctl; then
  say "SMART: smartctl present (run 'sudo smartctl -H /dev/...' for device health)"
elif [ "$OS" != "Darwin" ]; then
  say "SMART: smartctl not installed (install smartmontools for disk health)"
fi

# ----------------------------------------------------------- 5. software ---
section "Installed software"

if [ "$OS" = "Darwin" ]; then
  APPCOUNT=$(ls -1 /Applications 2>/dev/null | wc -l | tr -d ' ')
  say "Applications in /Applications: $APPCOUNT"
  have brew && say "Homebrew formulae: $(brew list --formula 2>/dev/null | wc -l | tr -d ' '), casks: $(brew list --cask 2>/dev/null | wc -l | tr -d ' ')"
  if have brew; then
    OUTDATED=$(brew outdated 2>/dev/null | wc -l | tr -d ' ')
    say "Homebrew packages outdated: $OUTDATED"
    [ "$OUTDATED" -gt 30 ] 2>/dev/null && finding LOW Software "Many outdated Homebrew packages" \
      "$OUTDATED formulae/casks are behind." "Run 'brew update && brew upgrade'."
  fi
else
  if have dpkg; then
    say "dpkg packages: $(dpkg -l 2>/dev/null | grep -c '^ii')"
    have apt && UPG=$(apt list --upgradable 2>/dev/null | grep -c upgradable) && say "Upgradable packages: $UPG"
    if [ -n "${UPG:-}" ] && [ "$UPG" -gt 50 ] 2>/dev/null; then
      finding MEDIUM Software "Many pending package upgrades" "$UPG packages upgradable." \
        "Run 'sudo apt update && sudo apt upgrade'; security fixes ship here."
    fi
  elif have rpm; then
    say "rpm packages: $(rpm -qa 2>/dev/null | wc -l)"
  elif have pacman; then
    say "pacman packages: $(pacman -Q 2>/dev/null | wc -l)"
  fi
  have snap && say "snap packages: $(snap list 2>/dev/null | tail -n +2 | wc -l)"
  have flatpak && say "flatpak apps: $(flatpak list 2>/dev/null | wc -l)"
fi

# ------------------------------------------------------------ 6. startup ---
section "Startup and background load"

if [ "$OS" = "Darwin" ]; then
  LA_USER=$(ls -1 "$HOME/Library/LaunchAgents" 2>/dev/null | wc -l | tr -d ' ')
  LA_SYS=$(ls -1 /Library/LaunchAgents 2>/dev/null | wc -l | tr -d ' ')
  LD_SYS=$(ls -1 /Library/LaunchDaemons 2>/dev/null | wc -l | tr -d ' ')
  say "LaunchAgents: $LA_USER (user) + $LA_SYS (system); LaunchDaemons: $LD_SYS"
  raw "$(ls -1 "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null)"
  TOTAL_LA=$((LA_USER + LA_SYS + LD_SYS))
  [ "$TOTAL_LA" -gt 40 ] && finding MEDIUM Startup "Heavy background agent load" \
    "$TOTAL_LA launch agents/daemons registered." \
    "Review with 'launchctl list'; leftover updaters from removed apps are common."
else
  if have systemctl; then
    ENABLED=$(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l)
    FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
    say "Enabled systemd units: $ENABLED, failed units: $FAILED"
    raw "$(systemctl --failed --no-legend 2>/dev/null)"
    [ "$FAILED" -gt 0 ] 2>/dev/null && finding MEDIUM Startup "Failed systemd units" \
      "$FAILED unit(s) are in a failed state." "Inspect with 'systemctl --failed' and its journal."
  fi
  AUTOSTART=$(ls -1 "$HOME/.config/autostart" 2>/dev/null | wc -l | tr -d ' ')
  say "Desktop autostart entries: $AUTOSTART"
fi

# -------------------------------------------------------- 7. performance ---
section "Live performance"

say "Top processes by memory:"
PS_OUT="$(ps -eo pid,pmem,pcpu,rss,comm 2>/dev/null | sort -k4 -rn | head -12)"
raw "$PS_OUT"
printf '%s\n' "$PS_OUT" | head -8 | sed 's/^/   /'

if [ "$OS" = "Darwin" ]; then
  say "Load average:$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')"
else
  [ -r /proc/loadavg ] && say "Load average: $(cut -d' ' -f1-3 /proc/loadavg)"
  CORES=$(nproc 2>/dev/null || echo 1)
  LOAD1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
  OVER=$(awk -v l="${LOAD1:-0}" -v c="${CORES:-1}" 'BEGIN{print (l > c*2) ? 1 : 0}')
  [ "$OVER" = "1" ] && finding MEDIUM Performance "Sustained high load" \
    "1-minute load $LOAD1 on $CORES cores." "Identify the busiest process in the list above."
fi

SWAPUSED=""
if [ "$OS" != "Darwin" ] && [ -r /proc/meminfo ]; then
  ST=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo); SF=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
  if [ -n "$ST" ] && [ "$ST" -gt 0 ]; then
    SWAPUSED=$(( (ST - SF) * 1024 ))
    say "Swap in use: $(human "$SWAPUSED") of $(human $((ST*1024)))"
    PCT=$(awk -v u="$((ST-SF))" -v t="$ST" 'BEGIN{printf "%.0f", u/t*100}')
    [ "$PCT" -gt 50 ] 2>/dev/null && finding MEDIUM Performance "Heavy swap use" \
      "${PCT}% of swap is in use." "The machine is short on RAM; close apps or add memory."
  fi
fi

# ----------------------------------------------------------- 8. security ---
section "Security posture"

if [ "$OS" = "Darwin" ]; then
  FV=$(fdesetup status 2>/dev/null)
  say "FileVault: ${FV:-unknown}"
  case "$FV" in
    *"FileVault is On"*) : ;;
    *) finding HIGH Security "Disk not encrypted" "FileVault status: ${FV:-unknown}." \
         "On a laptop holding personal legal/medical records, full-disk encryption is the highest-value fix. System Settings > Privacy & Security > FileVault." ;;
  esac

  FW=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
  say "Application firewall: ${FW:-unknown}"
  case "$FW" in
    *enabled*|*Enabled*) : ;;
    *) finding MEDIUM Security "Application firewall off" "${FW:-state unknown}." \
         "System Settings > Network > Firewall." ;;
  esac

  SIP=$(csrutil status 2>/dev/null)
  say "SIP: ${SIP:-unknown}"
  case "$SIP" in *disabled*) finding HIGH Security "System Integrity Protection disabled" \
      "$SIP" "Re-enable from Recovery unless you deliberately need it off." ;; esac

  GK=$(spctl --status 2>/dev/null)
  say "Gatekeeper: ${GK:-unknown}"
  case "$GK" in *disabled*) finding MEDIUM Security "Gatekeeper disabled" "$GK" \
      "Re-enable with 'sudo spctl --master-enable'." ;; esac

  SUS=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
  say "Automatic update checks: ${SUS:-unknown}"
  SHARING=$(launchctl list 2>/dev/null | grep -Ec 'screensharing|smbd|ftpd|sshd')
  say "Remote sharing services running: $SHARING"
  [ "$SHARING" -gt 0 ] 2>/dev/null && finding LOW Security "Remote access services active" \
    "$SHARING sharing service(s) loaded (screen sharing / SMB / SSH / FTP)." \
    "Turn off what you do not use in System Settings > General > Sharing."
else
  if have lsblk && lsblk -o TYPE 2>/dev/null | grep -q crypt; then
    say "Disk encryption: LUKS volume present"
  else
    say "Disk encryption: no LUKS mapping detected"
    finding HIGH Security "Disk may not be encrypted" "No dm-crypt/LUKS device found." \
      "Full-disk encryption is the single highest-value protection for a laptop that leaves the house."
  fi
  if have ufw; then
    UFW=$(ufw status 2>/dev/null | head -1)
    say "Firewall (ufw): ${UFW:-needs root}"
    case "$UFW" in *inactive*) finding MEDIUM Security "Firewall inactive" "$UFW" \
        "Enable with 'sudo ufw enable'." ;; esac
  elif have firewall-cmd; then
    say "Firewall (firewalld): $(firewall-cmd --state 2>/dev/null || echo unknown)"
  else
    say "Firewall: neither ufw nor firewalld found"
  fi
  have getenforce && say "SELinux: $(getenforce 2>/dev/null)"
  if have needrestart; then say "needrestart available for post-upgrade checks"; fi
fi

SUDOERS_NOPASS=$(grep -rhs 'NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "${SUDOERS_NOPASS:-0}" -gt 0 ] 2>/dev/null && finding MEDIUM Security "Passwordless sudo configured" \
  "$SUDOERS_NOPASS NOPASSWD rule(s) in the sudoers configuration." \
  "Convenient, but it means any process running as you can become root silently."

SSHKEYS=$(ls -1 "$HOME/.ssh"/id_* 2>/dev/null | grep -v '\.pub$' | wc -l | tr -d ' ')
say "SSH private keys in ~/.ssh: $SSHKEYS"
UNENCRYPTED=0
for k in "$HOME"/.ssh/id_*; do
  case "$k" in *.pub) continue ;; esac
  [ -f "$k" ] || continue
  grep -q 'ENCRYPTED\|bcrypt' "$k" 2>/dev/null || UNENCRYPTED=$((UNENCRYPTED + 1))
  PERM=$(ls -l "$k" 2>/dev/null | cut -c1-10)
  case "$PERM" in -rw-------|-r--------) : ;; *) finding MEDIUM Security "Loose permissions on SSH key" \
      "$k is $PERM." "chmod 600 the key; ssh will refuse it otherwise." ;; esac
done
[ "$UNENCRYPTED" -gt 0 ] && finding MEDIUM Security "Unencrypted SSH private key" \
  "$UNENCRYPTED private key(s) have no passphrase." \
  "Add one with 'ssh-keygen -p -f <key>'; an unencrypted key is a plaintext credential on disk."

# ------------------------------------------------------------ 9. network ---
section "Network"

if have ip; then
  raw "$(ip -brief address 2>/dev/null)"
  printf '%s\n' "$(ip -brief address 2>/dev/null | sed 's/^/   /')"
elif have ifconfig; then
  say "Interfaces: $(ifconfig -l 2>/dev/null)"
fi

if have ss; then
  LISTEN="$(ss -tlnp 2>/dev/null | tail -n +2)"
elif have lsof; then
  LISTEN="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | tail -n +2)"
else
  LISTEN=""
fi
LCOUNT=$(printf '%s\n' "$LISTEN" | grep -c . )
say "Listening TCP sockets: $LCOUNT"
raw "$LISTEN"
PUBLIC=$(printf '%s\n' "$LISTEN" | grep -cE '0\.0\.0\.0:|\*:|\[::\]:')
say "Bound to all interfaces: $PUBLIC"
[ "$PUBLIC" -gt 6 ] 2>/dev/null && finding LOW Network "Several services listening on all interfaces" \
  "$PUBLIC sockets are reachable from the local network." \
  "Bind development servers to 127.0.0.1; on shared Wi-Fi they are exposed."

[ -r /etc/resolv.conf ] && say "DNS: $(grep -s '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
[ -n "${http_proxy:-}${https_proxy:-}" ] && say "Proxy env set: ${https_proxy:-$http_proxy}"

# --------------------------------------------------------------- 10. dev ---
section "Developer toolchain"

for t in git node npm python3 pip3 go rustc java docker gh rg ffmpeg; do
  if have "$t"; then
    case "$t" in
      go)   V=$(go version 2>&1 | head -1) ;;
      java) V=$(java -version 2>&1 | grep -iv 'JAVA_TOOL_OPTIONS\|Picked up' | head -1) ;;
      *)    V=$("$t" --version 2>&1 | head -1) ;;
    esac
    printf '   %-8s %s\n' "$t" "$V"
    printf -- '- %-8s %s\n' "$t" "$V" >> "$BODY"
  fi
done

PATH_MISSING=0; PATH_LIST=""
OLDIFS="$IFS"; IFS=':'
for p in $PATH; do
  [ -z "$p" ] && continue
  if [ ! -d "$p" ]; then PATH_MISSING=$((PATH_MISSING + 1)); PATH_LIST="$PATH_LIST $p"; fi
done
IFS="$OLDIFS"
PATH_COUNT=$(printf '%s' "$PATH" | tr ':' '\n' | grep -c .)
PATH_DUPES=$(printf '%s' "$PATH" | tr ':' '\n' | grep . | sort | uniq -d | tr '\n' ' ')
say "PATH: $PATH_COUNT entries, $PATH_MISSING missing"
[ "$PATH_MISSING" -gt 0 ] && finding LOW Dev "PATH contains dead directories" \
  "Missing:$PATH_LIST" "Each miss costs a filesystem probe on every command lookup."
[ -n "$PATH_DUPES" ] && finding LOW Dev "Duplicate PATH entries" "$PATH_DUPES" \
  "Usually a shell rc file sourced twice."

if have git; then
  say "git user: $(git config --global user.name 2>/dev/null || echo 'not set') <$(git config --global user.email 2>/dev/null || echo 'not set')>"
fi

NM_COUNT=$(find "$HOME" -maxdepth 6 -type d -name node_modules -prune 2>/dev/null | wc -l | tr -d ' ')
if [ "$NM_COUNT" -gt 0 ]; then
  NM_SIZE=$(find "$HOME" -maxdepth 6 -type d -name node_modules -prune 2>/dev/null | xargs -I{} du -sk {} 2>/dev/null | awk '{s+=$1} END{print s*1024}')
  say "node_modules directories: $NM_COUNT using $(human "${NM_SIZE:-0}")"
  [ -n "$NM_SIZE" ] && [ "$NM_SIZE" -gt 21474836480 ] 2>/dev/null && finding LOW Dev "node_modules sprawl" \
    "$NM_COUNT node_modules trees using $(human "$NM_SIZE")." \
    "Delete them in dormant projects; 'npm install' rebuilds from the lockfile."
fi

# ------------------------------------------------------- 11. reliability ---
section "Reliability"

if [ "$OS" = "Darwin" ]; then
  CRASHES=$(ls -1 "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | wc -l | tr -d ' ')
  RECENT=$(find "$HOME/Library/Logs/DiagnosticReports" -type f -mtime -30 2>/dev/null | wc -l | tr -d ' ')
  say "Crash reports: $CRASHES total, $RECENT in the last 30 days"
  raw "$(find "$HOME/Library/Logs/DiagnosticReports" -type f -mtime -30 2>/dev/null | head -20)"
  [ "$RECENT" -gt 20 ] 2>/dev/null && finding MEDIUM Reliability "Frequent app crashes" \
    "$RECENT crash reports in the last 30 days." "Check which app repeats in the list above."
  PANICS=$(find "$HOME/Library/Logs/DiagnosticReports" -name '*.panic' -mtime -90 2>/dev/null | wc -l | tr -d ' ')
  [ "$PANICS" -gt 0 ] 2>/dev/null && finding HIGH Reliability "Kernel panics recorded" \
    "$PANICS panic report(s) in the last 90 days." "Usually failing RAM, a third-party kext, or a bad peripheral."
else
  if have journalctl; then
    ERRS=$(journalctl -p 3 --since '7 days ago' --no-pager 2>/dev/null | wc -l)
    say "Journal errors (priority<=3) in the last 7 days: $ERRS"
    raw "$(journalctl -p 3 --since '7 days ago' --no-pager 2>/dev/null | tail -30)"
    [ "$ERRS" -gt 500 ] 2>/dev/null && finding MEDIUM Reliability "High error volume in the journal" \
      "$ERRS error-level entries in 7 days." "Inspect with 'journalctl -p 3 -b' for the repeating source."
  fi
  OOM=$(dmesg 2>/dev/null | grep -ci 'out of memory\|oom-killer')
  [ "${OOM:-0}" -gt 0 ] 2>/dev/null && finding HIGH Reliability "OOM killer has fired" \
    "$OOM out-of-memory events in the kernel ring buffer." \
    "The machine ran out of RAM and killed processes; add swap or memory."
fi

# ------------------------------------------------------------ 12. backup ---
section "Backup and sync"

BACKUP_FOUND=0
if [ "$OS" = "Darwin" ]; then
  TM=$(tmutil destinationinfo 2>/dev/null | head -5)
  if [ -n "$TM" ]; then say "Time Machine destination configured"; BACKUP_FOUND=1; raw "$TM"
  else say "Time Machine: no destination configured"; fi
  LATEST=$(tmutil latestbackup 2>/dev/null)
  [ -n "$LATEST" ] && say "Latest backup: $LATEST"
fi
for d in "$HOME/Library/CloudStorage" "$HOME/OneDrive" "$HOME/Dropbox" "$HOME/Google Drive"; do
  [ -d "$d" ] && { say "Cloud sync folder present: $d"; BACKUP_FOUND=1; }
done
have restic && { say "restic installed"; BACKUP_FOUND=1; }
have borg && { say "borgbackup installed"; BACKUP_FOUND=1; }
have timeshift && { say "timeshift installed"; BACKUP_FOUND=1; }
if [ "$BACKUP_FOUND" -eq 0 ]; then
  say "No backup destination, cloud sync folder, or backup tool detected."
  finding HIGH Backup "No backup mechanism detected" \
    "No Time Machine destination, cloud sync folder, or backup tool found." \
    "A laptop holding an irreplaceable archive needs at least one automated copy off the device. For sensitive documents an encrypted external drive is safer than cloud sync."
fi

# --------------------------------------------------------- 13. deep scan ---
if [ "$DEEP" -eq 1 ]; then
  section "Deep scan (files over ${LARGE_MB} MB, duplicates)"
  say "Walking \$HOME. This can take several minutes..."
  LARGE="$(find "$HOME" -type f -size +"${LARGE_MB}"M 2>/dev/null -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -40)"
  if [ -z "$LARGE" ]; then
    LARGE="$(find "$HOME" -type f -size +"${LARGE_MB}"M -exec stat -f '%z%t%N' {} + 2>/dev/null | sort -rn | head -40)"
  fi
  raw "$LARGE"
  printf '%s\n' "$LARGE" | head -10 | awk -F'\t' '{printf "   %10.1f MB  %s\n", $1/1048576, $2}'

  say "Hashing same-size candidates over 10 MB..."
  HASHER=$(command -v sha256sum || command -v shasum)
  if [ -n "$HASHER" ]; then
    DUPES="$(find "$HOME" -type f -size +10M 2>/dev/null -print0 \
      | xargs -0 -n 50 "$HASHER" 2>/dev/null \
      | awk '{h=$1; $1=""; sub(/^ +/,""); print h"\t"$0}' \
      | sort | awk -F'\t' '{if ($1==prev) {if (!p) print prevline; print $0; p=1} else {p=0}; prev=$1; prevline=$0}' | head -60)"
    DUPCOUNT=$(printf '%s\n' "$DUPES" | grep -c .)
    say "Duplicate file lines (same SHA-256, over 10 MB): $DUPCOUNT"
    raw "$DUPES"
    [ "$DUPCOUNT" -gt 20 ] 2>/dev/null && finding MEDIUM Storage "Significant duplicate data" \
      "$DUPCOUNT large files share a hash with another copy." \
      "Review before deleting - keep one copy of anything archival, and never delete the only copy of a source export."
  fi
else
  say "Skipping large-file and duplicate scan (re-run with --deep to include it)."
fi

# ------------------------------------------------------------- 14. report ---
mkdir -p "$OUTDIR" 2>/dev/null

{
  printf '# Laptop audit - %s\n\n' "$HOSTNAME_S"
  printf 'Generated %s | OS: %s | deep scan: %s\n\n' "$(date '+%Y-%m-%d %H:%M')" "$OS" "$DEEP"
  printf '## Findings\n\n'
  if [ -s "$FINDINGS" ]; then
    for sev in CRITICAL HIGH MEDIUM LOW INFO; do
      n=$(awk -F'\t' -v s="$sev" '$1==s' "$FINDINGS" | grep -c .)
      [ "$n" -eq 0 ] && continue
      printf '### %s (%s)\n\n' "$sev" "$n"
      awk -F'\t' -v s="$sev" '$1==s {printf "- **[%s] %s**\n  - %s\n  - Fix: %s\n", $2, $3, $4, $5}' "$FINDINGS"
      printf '\n'
    done
  else
    printf 'Nothing flagged. Everything checked came back within normal thresholds.\n\n'
  fi
  cat "$BODY"
  printf '\n---\nThis report lists your hostname, user name, installed software, network configuration and file paths. Review before sharing it.\n'
} > "$REPORT"

printf '\n%s SUMMARY %s\n' "$C_YEL" "$C_OFF"
if [ -s "$FINDINGS" ]; then
  for sev in CRITICAL HIGH MEDIUM LOW INFO; do
    n=$(awk -F'\t' -v s="$sev" '$1==s' "$FINDINGS" | grep -c .)
    [ "$n" -eq 0 ] && continue
    case "$sev" in CRITICAL|HIGH) col="$C_RED" ;; MEDIUM) col="$C_YEL" ;; *) col="$C_GRY" ;; esac
    printf '%s  %-9s %s%s\n' "$col" "$sev" "$n" "$C_OFF"
    awk -F'\t' -v s="$sev" '$1==s {printf "      - [%s] %s\n", $2, $3}' "$FINDINGS"
  done
else
  printf '  Nothing flagged.\n'
fi
printf '\n  Report: %s\n' "$REPORT"
printf '%s  Nothing was changed on this machine.%s\n\n' "$C_GRY" "$C_OFF"
