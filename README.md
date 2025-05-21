# CLI Tools

A collection of command-line interface tools and scripts for various automation tasks.

## Scripts

### cm.ps1

This script fetches contracts from the eggcoop.org API and generates commands for checking minimums. It:

- Retrieves contracts from the API
- Filters contracts for the current day
- Generates commands with proper time formatting in CST/CDT timezone
- Handles error cases appropriately

## Usage

```powershell
.\scripts\cm.ps1
```

## Requirements

- PowerShell 7.3 or higher
- Internet connection to access the API
```
