# CLI Tools

A collection of command-line interface tools and scripts for various automation tasks.

## Installed CLI Tools

The following CLI tools are installed and available for use:

### edit
Microsoft's new open-source command-line text editor for Windows. A modern, lightweight terminal-based editor that provides an intuitive editing experience directly from the command line.

### dive
A powerful tool for exploring Docker image layers and analyzing their contents. Helps optimize Docker images by showing what's in each layer, identifying wasted space, and discovering ways to shrink image size.

### lazygit
A simple and intuitive terminal UI for Git commands. Provides a beautiful interface for staging files, viewing diffs, managing branches, and performing Git operations without memorizing complex command syntax.

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
