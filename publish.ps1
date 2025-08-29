# PowerShell script to publish the CLI Tools as a self-contained executable
# This will create a single .exe file that includes all dependencies and scripts
# and optionally copy it to System32 for global access

param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputPath = ".\publish",
    [switch]$CopyToSystem32
)

Write-Host "Publishing HemSoft CLI Tools as self-contained executable..." -ForegroundColor Green
Write-Host "Configuration: $Configuration" -ForegroundColor Yellow
Write-Host "Runtime: $Runtime" -ForegroundColor Yellow
Write-Host "Output Path: $OutputPath" -ForegroundColor Yellow
Write-Host "Copy to System32: $CopyToSystem32" -ForegroundColor Yellow
Write-Host

# Change to the project directory
$projectPath = ".\src\HemSoft.CLITools.Console"
Set-Location $projectPath

try {
    # Clean any previous builds
    Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
    dotnet clean -c $Configuration    # Publish the application
    Write-Host "Publishing application..." -ForegroundColor Yellow
    dotnet publish -c $Configuration -r $Runtime --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $OutputPath

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Successfully published!" -ForegroundColor Green
        $exePath = Resolve-Path "$OutputPath\HemSoft.CLITools.Console.exe"
        Write-Host "Self-contained executable location:" -ForegroundColor Green
        Write-Host "  $exePath" -ForegroundColor Cyan
        Write-Host "`nThe executable includes all scripts and dependencies." -ForegroundColor Green
        Write-Host "You can copy this single file to any Windows machine and run it." -ForegroundColor Green

        # Copy to System32 if requested
        if ($CopyToSystem32) {
            Write-Host "`nCopying to System32 for global access..." -ForegroundColor Yellow

            # Check if running as Administrator
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            if ($isAdmin) {
                try {
                    $system32Path = "C:\Windows\System32\HemSoftCliTools.exe"
                    Copy-Item -Path $exePath -Destination $system32Path -Force
                    Write-Host "✅ Successfully copied to: $system32Path" -ForegroundColor Green
                    Write-Host "You can now run 'HemSoftCliTools' from anywhere in the command line!" -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ Failed to copy to System32: $_" -ForegroundColor Red
                    Write-Host "You can manually copy the executable to System32 if needed." -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "⚠️  Administrator privileges required to copy to System32." -ForegroundColor Yellow
                Write-Host "Please run this script as Administrator, or manually copy the executable to System32." -ForegroundColor Yellow
                Write-Host "Manual copy command: Copy-Item '$exePath' 'C:\Windows\System32\HemSoftCliTools.exe'" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "`n❌ Publish failed!" -ForegroundColor Red
    }
}
catch {
    Write-Host "`n❌ Error during publish: $_" -ForegroundColor Red
}
finally {
    # Return to original directory
    Set-Location ..\..
}

Write-Host "`nPress any key to continue..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
