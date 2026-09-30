# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026

### Added
- Modernized rewrite of ConfigMgr Client Health (v0.8.3) by Anders Rødland.
- Typed configuration model (`ClientHealthConfig` class) replacing XML string-parsing getters.
- CIM-only implementation (no WMI/`$PowerShellVersion` branching).
- CMTrace-compatible structured logging.
- Parameterized SQL reporting (table auto-created).
- REST webservice reporting via `Invoke-RestMethod`.
- Pester test suite.
- Sample `config.xml`.
