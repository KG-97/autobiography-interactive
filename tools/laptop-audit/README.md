# Laptop audit

Two self-contained scripts that audit a laptop and write a report you can read
or paste back into a chat for interpretation.

| Script | Platform |
| --- | --- |
| `Invoke-LaptopAudit.ps1` | Windows (PowerShell 5.1 or 7.x) |
| `laptop-audit.sh` | macOS and Linux |

Both are **read-only**. They change no setting, service, registry key or file;
the only thing written is the report itself.

## Run it

**Windows** — open PowerShell in the folder containing the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-LaptopAudit.ps1
```

Run it from an *administrator* PowerShell for the full picture: BitLocker
state, TPM, boot timings and the full event log are not readable otherwise.
Without elevation the script still runs and marks those checks as needing admin.

**macOS / Linux:**

```bash
bash laptop-audit.sh
```

**Options** (both scripts): add `-Deep` / `--deep` to also scan the user
profile for large files and duplicate files. That walk takes minutes on a big
profile, which is why it is opt-in. `-OutDir` / `--out DIR` changes where the
report lands (default: Desktop on Windows, home directory elsewhere).

## What it checks

- **System** — OS build, model, firmware, uptime, pending reboot
- **Hardware** — CPU, RAM totals and current pressure, GPU and driver age
- **Battery** — charge, cycle count, full-charge capacity against design
  capacity (the real wear number)
- **Storage** — free space per volume, disk health and SMART failure
  prediction, largest folders, temp/cache footprint, recycle bin
- **Software** — installed programs, largest installs, end-of-life runtimes
  (Flash, Java 6/7, Python 2), duplicate AV suites and "optimizer" nuisanceware
- **Startup** — everything that launches at sign-in, logon scheduled tasks,
  third-party auto-start services
- **Performance** — top processes by memory, CPU load, swap, recent boot times
- **Security** — Defender/AV state and signature age, firewall profiles, disk
  encryption, UAC, Secure Boot, TPM, RDP, SMBv1, local admins, passwordless
  accounts, SSH key permissions, patch recency
- **Network** — active adapters, DNS, listening sockets, proxy configuration
- **Developer toolchain** — installed tool versions, PATH dead entries,
  duplicates and length limit, git identity, `node_modules` sprawl
- **Reliability** — error volume in the event log/journal, crash dumps, kernel
  panics, OOM kills
- **Backup** — whether *any* automated copy of the machine exists

Each check that trips a threshold becomes a finding with a severity
(CRITICAL / HIGH / MEDIUM / LOW / INFO), what was measured, and what to do
about it. The console prints a ranked summary; the report holds the detail.

## Output

- `laptop-audit_<host>_<date>.md` — findings plus every section's raw data
- `laptop-audit_<host>_<date>.json` — the same data, machine-readable
  (Windows script only)

## Before you share the report

The report contains your hostname, user name, the full list of installed
software, network configuration, and file paths from your profile — a decent
map of the machine. That is fine to paste into a chat you trust; it is not
something to post publicly. If the machine holds sensitive material, skim the
storage and deep-scan sections for file paths you would rather not include
before sharing.

## What these scripts never do

No writes outside the report directory. No registry or configuration changes.
No network calls. No file contents are read — only names, sizes and, in deep
mode, hashes.
