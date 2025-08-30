# Runs the console project from the solution root
# Usage: ./run.ps1 [-- args to app]

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'

# Resolve project path robustly relative to this script location
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $root 'src/HemSoft.CLITools.Console/HemSoft.CLITools.Console.csproj'

if (-not (Test-Path $projectPath)) {
    Write-Error "Project file not found: $projectPath"
}

Write-Host "Running HemSoft CLI Tools..." -ForegroundColor Green

# Forward remaining arguments to the application after --
if ($Args -and $Args.Length -gt 0) {
    dotnet run --project "$projectPath" -- $Args
}
else {
    dotnet run --project "$projectPath"
}
