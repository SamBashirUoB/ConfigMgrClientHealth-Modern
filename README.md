# ConfigMgr Client Health (Modern)

A modernized rewrite of the classic [ConfigMgr Client Health](https://github.com/AndersRodland/ConfigMgrClientHealth) tool by Anders Rødland.

It keeps the **same feature set** — validate and automatically remediate common Configuration Manager (SCCM) client issues on Windows endpoints — but uses modern PowerShell practices:

- **CIM instead of WMI** — no more `$PowerShellVersion` branching.
- **Typed configuration** — a strongly-typed class replaces dozens of fragile XML string-parsing getters.
- **Parameterized SQL** — no string-concatenated queries.
- **Structured logging** — CMTrace-compatible output that still opens in CMTrace / OneTrace.
- **Pester tests** — the original had none.

## Features

Health checks (each can be enabled/disabled in `config.xml`):

| Check | What it does |
|-------|--------------|
| Client install | Installs/reinstalls the client from the share if missing or below minimum version |
| Client version | Verifies installed version against the configured minimum |
| Site code | Verifies and corrects the assigned site code |
| Cache size | Verifies/sets the client cache size (MB or % of disk) |
| Log size | Verifies/sets max log size and history |
| Local database | Detects a broken client (missing `.sdf` files) |
| WMI | Verifies repository consistency; repairs if corrupt |
| CcmSQLCE log | Detects a corrupt local database |
| Provisioning mode | Detects and clears provisioning mode |
| Services | Verifies startup type/state of configured services |
| Admin share | Verifies/recreates the `C$` admin share |
| DNS | Verifies local FQDN resolves correctly |
| Drivers | Detects faulty/missing device drivers |
| Updates | Installs required updates from the update share |
| Patch level | Reports the last installed patch date |
| Pending reboot | Detects pending reboot (CBS/WU/SCCM) |
| Hardware inventory | Triggers a scan if stale |
| Software metering | Installs the SWMTRP driver if missing |
| BITS | Clears stuck BITS jobs |
| Client settings | Removes stale task-sequence client settings |
| State messages | Refreshes compliance state |
| WUAHandler | Repairs a broken `registry.pol` |
| Certificate | Recreates a broken client certificate |

## Requirements

- Windows (PowerShell 5.1+ or PowerShell 7+)
- Local admin rights for remediation actions
- ConfigMgr client installed (for most checks)

## Usage

```powershell
# Load the module
Import-Module .\ConfigMgrClientHealth\ConfigMgrClientHealth.psd1

# Validate your config
Test-ClientHealthConfig -Path .\config.xml

# Run checks + remediation
Invoke-ClientHealthCheck -ConfigPath .\config.xml

# Run checks only (no remediation)
Invoke-ClientHealthCheck -ConfigPath .\config.xml -SkipRemediation

# Export a CSV report
$log = Invoke-ClientHealthCheck -ConfigPath .\config.xml
Get-ClientHealthReport -Log $log -Path .\report.csv
```

## Configuration

Copy `config.xml` and edit to match your environment. Key sections:

- **`<Client>`** — minimum version, site code, domain, install share, cache/log settings.
- **`<Service>`** — services to verify (startup type, state).
- **`<Option>`** — which checks run and whether they auto-fix.
- **`<Remediation>`** — which remediation actions are enabled.
- **`<Log>`** — local log file, file share, SQL, and webservice reporting.

## Reporting

Results can be written to:

1. **Local CMTrace log** — `C:\ClientHealth\ClientHealth.log` (or your configured path).
2. **SQL database** — parameterized insert into `dbo.Clients` (table auto-created).
3. **REST webservice** — `PUT /Clients` with the report as JSON.

## Development

```powershell
# Run tests
Invoke-Pester .\tests
```

## License

MIT. See [LICENSE](LICENSE).

## Credits

Original tool: [AndersRodland/ConfigMgrClientHealth](https://github.com/AndersRodland/ConfigMgrClientHealth) (v0.8.3).
