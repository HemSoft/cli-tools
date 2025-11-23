# CLI Tools

A collection of command-line interface tools and scripts for various automation tasks.

## Features

- **Interactive Menu**: Browse and launch tools from a user-friendly Spectre.Console-powered interface
- **Import Tool**: Guided wizard to add new tools to the ecosystem (first option in the menu)
- **Script Management**: Automatic copying and organization of PowerShell scripts
- **Parameter Configuration**: Support for static parameters and runtime arguments
- **Interactive Tools**: Special handling for tools that need full console control

## Importing New Tools

The CLI Tools ecosystem makes it easy to add new tools through the **Import Tool** wizard (highlighted in yellow as the first menu option). The wizard guides you through:

1. **Basic Information**: Name, description, and version
2. **Tool Type**: PowerShell script, executable on PATH, or executable with full path
3. **Verification**: Optional tool execution test
4. **Interactivity**: Configure whether the tool needs full console control
5. **Parameters**: Add static parameters passed to the tool every time
6. **Runtime Arguments**: Configure prompts shown to users before running the tool
7. **Review**: Confirm configuration before saving

The import process automatically:
- Copies PowerShell scripts to the `scripts` directory
- Verifies tool availability
- Tests tool execution
- Updates `appsettings.json` with proper configuration
- Creates backups before modifying configuration

📖 **For detailed import instructions, examples, and troubleshooting, see [IMPORT-GUIDE.md](IMPORT-GUIDE.md)**

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

## Code Quality

This project maintains high code quality standards through a combination of `.editorconfig` rules, SonarQube analysis, and build-time enforcement.

### .editorconfig & Style Rules

The `.editorconfig` file at the root of the repository defines the coding style and conventions. Key rules include:

- **File-scoped namespaces**: Reduces indentation levels.
- **Inside-namespace usings**: Keeps dependencies scoped.
- **Primary constructors**: Promotes concise class definitions.
- **Expression-bodied members**: Encourages one-liners for simple methods/properties.
- **Collection expressions**: Uses modern C# 12 syntax.

### SonarQube Integration

We use `SonarAnalyzer.CSharp` to perform advanced static analysis.
- **Configuration**: `SonarLint.xml` configures specific rules, such as **Cognitive Complexity (S3776)** with a threshold of 15.
- **Enforcement**: Analyzers run during the build process, reporting issues as warnings.

### Build & Format

Code style is enforced during the build process via the `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` property in the project file.

- **Check**: Run `dotnet build` to see any code style or quality warnings.
- **Fix**: Run `dotnet format` to automatically fix style violations and ensure the codebase adheres to the defined standards.
