<#
Minimal publish script
Builds and publishes HemSoft CLI Tools as a single-file, self-contained executable
and copies it to F:\Tools\HemSoftCLITools.exe
#>

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $root 'src\HemSoft.CLITools.Console'
$publishDir = Join-Path $projectPath 'publish'

Write-Host 'Publishing HemSoft CLI Tools...' -ForegroundColor Green

try {
    Set-Location $projectPath

    if (Test-Path $publishDir) {
        Remove-Item -Recurse -Force $publishDir
    }

    # Publish single-file, self-contained for Windows x64
    dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $publishDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

    $srcExe = Join-Path $publishDir 'HemSoft.CLITools.Console.exe'
    if (-not (Test-Path $srcExe)) { throw "Published executable not found: $srcExe" }

    $destDir = 'F:\Tools'
    $destExe = Join-Path $destDir 'HemSoftCLITools.exe'
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Copy-Item -Path $srcExe -Destination $destExe -Force

    Write-Host "Done -> $destExe" -ForegroundColor Green
}
catch {
    Write-Error $_
}
finally {
    Set-Location $root
}
