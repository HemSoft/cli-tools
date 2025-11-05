#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Import a new CLI tool into the HemSoft CLI Tools ecosystem.

.DESCRIPTION
    This script guides users through importing a new tool by:
    - Collecting tool metadata (name, description, version)
    - Determining tool type (script or executable)
    - Copying scripts to the scripts directory if needed
    - Verifying tool availability
    - Configuring parameters and runtime arguments
    - Updating appsettings.json with the new tool

.NOTES
    This is an interactive tool that provides a guided import experience.
#>

using namespace System.Collections.Generic

# Import required modules
$ErrorActionPreference = "Stop"

# Get the base directory (where the script is located)
$scriptsDir = Split-Path -Parent $PSCommandPath
$baseDir = Split-Path -Parent $scriptsDir

# Navigate to source appsettings.json if we're in bin output
if ($baseDir -match '\\bin\\(Debug|Release)\\') {
    # We're in bin output, navigate to src project directory
    $projectRoot = $baseDir -replace '\\bin\\(Debug|Release)\\.*', ''
    $appSettingsPath = Join-Path $projectRoot "appsettings.json"
} else {
    # We're already in the correct location
    $appSettingsPath = Join-Path $baseDir "appsettings.json"
}

# Spectre.Console-like formatting functions
function Write-Title {
    param([string]$Text)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "─── $Text " -ForegroundColor Yellow -NoNewline
    Write-Host ("─" * (60 - $Text.Length)) -ForegroundColor Yellow
    Write-Host ""
}

function Write-Success {
    param([string]$Text)
    Write-Host "✓ " -ForegroundColor Green -NoNewline
    Write-Host $Text
}

function Write-Info {
    param([string]$Text)
    Write-Host "ℹ " -ForegroundColor Cyan -NoNewline
    Write-Host $Text
}

function Write-Warning {
    param([string]$Text)
    Write-Host "⚠ " -ForegroundColor Yellow -NoNewline
    Write-Host $Text
}

function Write-Error {
    param([string]$Text)
    Write-Host "✗ " -ForegroundColor Red -NoNewline
    Write-Host $Text
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [string]$Default = ""
    )

    Write-Host $Prompt -ForegroundColor Yellow
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($Default -and $Options[$i] -eq $Default) { " (default)" } else { "" }
        Write-Host "  [$($i + 1)] $($Options[$i])$marker" -ForegroundColor Gray
    }

    do {
        Write-Host "Select [1-$($Options.Count)]: " -ForegroundColor Cyan -NoNewline
        $input = Read-Host

        if ([string]::IsNullOrWhiteSpace($input) -and $Default) {
            return $Default
        }

        if ($input -match '^\d+$') {
            $index = [int]$input - 1
            if ($index -ge 0 -and $index -lt $Options.Count) {
                return $Options[$index]
            }
        }
        Write-Warning "Invalid selection. Please try again."
    } while ($true)
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )

    $defaultText = if ($Default) { "Y/n" } else { "y/N" }
    Write-Host "$Prompt [$defaultText]: " -ForegroundColor Yellow -NoNewline
    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Default
    }

    return $input -match '^[yY]'
}

function Read-Input {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [bool]$Required = $true
    )

    do {
        $defaultText = if ($Default) { " [default: $Default]" } else { "" }
        Write-Host "$Prompt$defaultText" -ForegroundColor Yellow -NoNewline
        Write-Host ": " -NoNewline
        $input = Read-Host

        if ([string]::IsNullOrWhiteSpace($input)) {
            if ($Default) {
                return $Default
            }
            if (-not $Required) {
                return ""
            }
            Write-Warning "This field is required. Please provide a value."
        } else {
            return $input
        }
    } while ($true)
}

function Test-CommandExists {
    param([string]$Command)

    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-ToolExecution {
    param(
        [string]$Command,
        [string]$Arguments = ""
    )

    Write-Info "Testing tool execution..."

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = if ($Command.EndsWith(".ps1")) { "pwsh.exe" } else { $Command }
        $psi.Arguments = if ($Command.EndsWith(".ps1")) { "-ExecutionPolicy Bypass -NoProfile -File `"$Command`" --help" } else { "--help" }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $null = $process.Start()
        $process.WaitForExit(5000) | Out-Null

        if (-not $process.HasExited) {
            $process.Kill()
            Write-Warning "Tool test timed out (this may be normal for some tools)"
            return $true
        }

        Write-Success "Tool execution test passed"
        return $true
    } catch {
        Write-Warning "Tool test failed: $($_.Exception.Message)"
        Write-Info "Tool may still work - some tools don't support --help flag"
        return Read-YesNo "Continue anyway?" $true
    }
}

function Get-AppSettings {
    if (-not (Test-Path $appSettingsPath)) {
        Write-Error "appsettings.json not found at: $appSettingsPath"
        exit 1
    }

    try {
        $json = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        return $json
    } catch {
        Write-Error "Failed to parse appsettings.json: $($_.Exception.Message)"
        exit 1
    }
}

function Save-AppSettings {
    param($Settings)

    try {
        # Create backup
        $backupPath = "$appSettingsPath.backup"
        Copy-Item $appSettingsPath $backupPath -Force
        Write-Info "Backup created: $backupPath"

        # Save with proper formatting
        $json = $Settings | ConvertTo-Json -Depth 10
        $json | Set-Content $appSettingsPath -Encoding UTF8

        Write-Success "appsettings.json updated successfully"
    } catch {
        Write-Error "Failed to save appsettings.json: $($_.Exception.Message)"
        exit 1
    }
}

# Main script execution
Clear-Host

Write-Title "HemSoft CLI Tools - Import Tool"

Write-Info "This wizard will guide you through importing a new tool into the CLI Tools ecosystem."
Write-Host ""

# Step 1: Collect basic information
Write-Section "Step 1: Basic Information"

$toolName = Read-Input "Tool Name" -Required $true
$toolDescription = Read-Input "Tool Description" -Required $true
$toolVersion = Read-Input "Tool Version" -Default "1.0.0"

# Step 2: Determine tool type
Write-Section "Step 2: Tool Type"

$toolType = Read-Choice "What type of tool are you importing?" @(
    "PowerShell Script (.ps1)",
    "Executable on PATH",
    "Executable with full path"
)

$command = ""
$needsCopy = $false

switch ($toolType) {
    "PowerShell Script (.ps1)" {
        $scriptPath = Read-Input "Enter the path to the PowerShell script"

        if (-not (Test-Path $scriptPath)) {
            Write-Error "Script file not found: $scriptPath"
            exit 1
        }

        $scriptName = Split-Path -Leaf $scriptPath

        if (-not $scriptName.EndsWith(".ps1")) {
            Write-Error "File must be a PowerShell script (.ps1)"
            exit 1
        }

        # Copy script to scripts directory
        $targetPath = Join-Path $scriptsDir $scriptName

        if (Test-Path $targetPath) {
            if (-not (Read-YesNo "Script already exists in scripts directory. Overwrite?" $false)) {
                Write-Info "Using existing script in scripts directory"
            } else {
                Copy-Item $scriptPath $targetPath -Force
                Write-Success "Script copied to: $targetPath"
            }
        } else {
            Copy-Item $scriptPath $targetPath -Force
            Write-Success "Script copied to: $targetPath"
        }

        $command = $scriptName
    }

    "Executable on PATH" {
        $execName = Read-Input "Enter the executable name (e.g., 'git', 'docker')"

        if (-not (Test-CommandExists $execName)) {
            Write-Warning "Command '$execName' not found on PATH"
            if (-not (Read-YesNo "Continue anyway?" $false)) {
                exit 1
            }
        } else {
            Write-Success "Command '$execName' found on PATH"
        }

        $command = $execName
    }

    "Executable with full path" {
        $execPath = Read-Input "Enter the full path to the executable"

        if (-not (Test-Path $execPath)) {
            Write-Warning "Executable not found: $execPath"
            if (-not (Read-YesNo "Continue anyway?" $false)) {
                exit 1
            }
        } else {
            Write-Success "Executable found: $execPath"
        }

        $command = $execPath
    }
}

# Step 3: Test execution
Write-Section "Step 3: Verification"

if (Read-YesNo "Test tool execution?" $true) {
    Test-ToolExecution $command
}

# Step 4: Configure interactivity
Write-Section "Step 4: Interactivity"

Write-Info "Interactive tools are launched in the current console and take control (e.g., vim, lazygit, mc)."
Write-Info "Non-interactive tools run and return output to the CLI Tools interface."

$isInteractive = Read-YesNo "Is this an interactive tool?" $false

# Step 5: Configure parameters
Write-Section "Step 5: Parameters"

Write-Info "Parameters are static values passed to the tool every time it runs."
Write-Info "Examples: API URLs, default timeouts, configuration paths, etc."

$parameters = @{}

if (Read-YesNo "Add static parameters?" $false) {
    do {
        $paramName = Read-Input "Parameter name" -Required $false

        if ([string]::IsNullOrWhiteSpace($paramName)) {
            break
        }

        $paramValue = Read-Input "Parameter value for '$paramName'" -Required $true
        $parameters[$paramName] = $paramValue

        Write-Success "Parameter added: $paramName = $paramValue"

    } while (Read-YesNo "Add another parameter?" $false)
}

# Step 6: Configure runtime arguments
Write-Section "Step 6: Runtime Arguments"

Write-Info "Runtime arguments are prompted from the user each time the tool is run."
Write-Info "Examples: Docker image name, file path, search query, etc."

$runtimeArgs = @()

if (Read-YesNo "Add runtime arguments?" $false) {
    do {
        $argName = Read-Input "Argument name (e.g., 'image', 'query')"
        $argPrompt = Read-Input "Prompt text (shown to user)"
        $argRequired = Read-YesNo "Is this argument required?" $true
        $argDefault = Read-Input "Default value (optional)" -Required $false

        $runtimeArg = @{
            Name = $argName
            Prompt = $argPrompt
            Required = $argRequired
        }

        if (-not [string]::IsNullOrWhiteSpace($argDefault)) {
            $runtimeArg.DefaultValue = $argDefault
        }

        $runtimeArgs += $runtimeArg
        Write-Success "Runtime argument added: $argName"

    } while (Read-YesNo "Add another runtime argument?" $false)
}

# Step 7: Review and confirm
Write-Section "Step 7: Review Configuration"

Write-Host ""
Write-Host "Tool Configuration Summary:" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  Name:        " -ForegroundColor Gray -NoNewline; Write-Host $toolName -ForegroundColor White
Write-Host "  Description: " -ForegroundColor Gray -NoNewline; Write-Host $toolDescription -ForegroundColor White
Write-Host "  Command:     " -ForegroundColor Gray -NoNewline; Write-Host $command -ForegroundColor White
Write-Host "  Version:     " -ForegroundColor Gray -NoNewline; Write-Host $toolVersion -ForegroundColor White
Write-Host "  Interactive: " -ForegroundColor Gray -NoNewline; Write-Host $isInteractive -ForegroundColor White

if ($parameters.Count -gt 0) {
    Write-Host "  Parameters:  " -ForegroundColor Gray
    foreach ($key in $parameters.Keys) {
        Write-Host "    • $key = $($parameters[$key])" -ForegroundColor DarkGray
    }
}

if ($runtimeArgs.Count -gt 0) {
    Write-Host "  Runtime Args:" -ForegroundColor Gray
    foreach ($arg in $runtimeArgs) {
        $req = if ($arg.Required) { "required" } else { "optional" }
        Write-Host "    • $($arg.Name) ($req): $($arg.Prompt)" -ForegroundColor DarkGray
    }
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""

if (-not (Read-YesNo "Proceed with import?" $true)) {
    Write-Warning "Import cancelled by user"
    exit 0
}

# Step 8: Update appsettings.json
Write-Section "Step 8: Updating Configuration"

try {
    $appSettings = Get-AppSettings

    # Check if tool already exists
    $existingTool = $appSettings.AppSettings.CliTools | Where-Object { $_.Name -eq $toolName }

    if ($existingTool) {
        Write-Warning "Tool '$toolName' already exists in configuration"
        if (-not (Read-YesNo "Update existing tool?" $false)) {
            Write-Info "Import cancelled"
            exit 0
        }

        # Remove existing tool
        $appSettings.AppSettings.CliTools = @($appSettings.AppSettings.CliTools | Where-Object { $_.Name -ne $toolName })
    }

    # Create new tool configuration
    $newTool = [PSCustomObject]@{
        Name = $toolName
        Description = $toolDescription
        Command = $command
        Version = $toolVersion
        IsInteractive = $isInteractive
        Parameters = $parameters
    }

    if ($runtimeArgs.Count -gt 0) {
        $newTool | Add-Member -NotePropertyName "RuntimeArguments" -NotePropertyValue $runtimeArgs
    }

    # Add tool to configuration
    # Ensure CliTools is treated as an array and use array concatenation
    $currentTools = @($appSettings.AppSettings.CliTools)
    $appSettings.AppSettings.CliTools = $currentTools + $newTool    # Save configuration
    Save-AppSettings $appSettings

    Write-Host ""
    Write-Success "Tool '$toolName' imported successfully!"
    Write-Host ""
    Write-Info "The tool is now available in the CLI Tools menu."
    Write-Info "You can manually edit appsettings.json to make further adjustments."

} catch {
    Write-Error "Failed to import tool: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
