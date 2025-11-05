#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Interactive Docker image explorer that displays images in a paginated list and launches dive.

.DESCRIPTION
    Lists Docker images sorted by creation date (newest first), displays them in a paginated format
    with 20 items per page, and allows selection by number to launch dive for image analysis.
    Supports partial image name matching for quick access.

.EXAMPLE
    .\docker-image-explorer.ps1
#>

# Prompt for image name
Write-Host "Docker Image Explorer" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
$imageName = Read-Host "Enter image name (or press Enter for selection menu)"
Write-Host ""

# Get all Docker images with details
try {
    $images = docker images --format json | ConvertFrom-Json
    if (-not $images) {
        Write-Host "No Docker images found." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "Error retrieving Docker images: $_" -ForegroundColor Red
    exit 1
}

# Filter and sort images
$filteredImages = @()
foreach ($image in $images) {
    $repo = $image.Repository
    $tag = $image.Tag

    # Skip <none> images and images with long GUIDs (likely VSCode dev containers or build artifacts)
    if ($repo -eq "<none>" -or $tag -eq "<none>") {
        continue
    }

    # Skip images with very long hex strings in the name (VSCode containers, build artifacts)
    if ($repo -match '^[a-f0-9]{40,}$' -or $repo -match 'vsc-.*-[a-f0-9]{64,}') {
        continue
    }

    $filteredImages += @{
        Repository = $repo
        Tag = $tag
        Created = $image.CreatedAt
        Size = $image.Size
    }
}

# Sort by creation date (newest first)
# Docker's date format includes timezone abbreviations that need to be stripped
$sortedImages = $filteredImages | Sort-Object {
    try {
        # Remove timezone abbreviation (e.g., "EDT", "EST") from the end
        $dateStr = $_.Created -replace '\s+[A-Z]{3,4}$', ''
        [datetime]::Parse($dateStr)
    } catch {
        [datetime]::MinValue
    }
} -Descending

if ($sortedImages.Count -eq 0) {
    Write-Host "No suitable Docker images found." -ForegroundColor Red
    exit 1
}

# If user entered an image name, try to match it
if (-not [string]::IsNullOrWhiteSpace($imageName)) {
    $matchedImages = $sortedImages | Where-Object {
        $repoTag = "{0}:{1}" -f $_.Repository, $_.Tag
        $repoTag -like "*$imageName*"
    }

    if ($matchedImages.Count -eq 0) {
        Write-Host "No images found matching '$imageName'." -ForegroundColor Yellow
        Write-Host "Returning to main menu..." -ForegroundColor Yellow
        Write-Host ""
        Start-Sleep -Seconds 2
    }
    else {
        # Pick the first match and launch dive immediately
        $selectedImage = $matchedImages[0]
        $imageFullName = "{0}:{1}" -f $selectedImage.Repository, $selectedImage.Tag

        if ($matchedImages.Count -gt 1) {
            Write-Host "Found $($matchedImages.Count) matching images. Selecting first match: $imageFullName" -ForegroundColor Green
        }
        else {
            Write-Host "Found match: $imageFullName" -ForegroundColor Green
        }
        Write-Host ""

        try {
            & dive $imageFullName
            exit 0
        }
        catch {
            Write-Host "Error launching dive: $_" -ForegroundColor Red
            exit 1
        }
    }
}

$pageSize = 20
$currentPage = 0
$selectedImage = $null

# Helper function to display a page of images
function Show-ImagePage {
    param([int]$PageNumber)

    $startIndex = $PageNumber * $pageSize
    $endIndex = [Math]::Min($startIndex + $pageSize - 1, $sortedImages.Count - 1)
    $totalPages = [Math]::Ceiling($sortedImages.Count / $pageSize)

    Write-Host ""
    Write-Host "Docker Images (Page $($PageNumber + 1) of $totalPages)" -ForegroundColor Cyan
    Write-Host ("=" * 120) -ForegroundColor Cyan
    Write-Host ("{0,-3} {1,-50} {2,-20} {3,-20} {4,-20}" -f "#", "Repository:Tag", "Created", "Size", "") -ForegroundColor Yellow
    Write-Host ("=" * 120) -ForegroundColor Cyan

    for ($i = $startIndex; $i -le $endIndex; $i++) {
        $img = $sortedImages[$i]
        $displayNum = $i + 1
        $repoTag = "{0}:{1}" -f $img.Repository, $img.Tag
        $created = if ($img.Created) {
            try {
                # Remove timezone abbreviation before parsing
                $dateStr = $img.Created -replace '\s+[A-Z]{3,4}$', ''
                ([datetime]::Parse($dateStr)).ToString("yyyy-MM-dd HH:mm")
            } catch {
                $img.Created
            }
        } else {
            "Unknown"
        }
        $size = $img.Size

        Write-Host ("{0,-3} {1,-50} {2,-20} {3,-20}" -f $displayNum, $repoTag, $created, $size)
    }

    Write-Host ("=" * 120) -ForegroundColor Cyan
    Write-Host ""
}

# Main loop for navigation
while ($true) {
    Show-ImagePage -PageNumber $currentPage

    $totalPages = [Math]::Ceiling($sortedImages.Count / $pageSize)

    # Show navigation options
    $navOptions = @()
    if ($currentPage -gt 0) {
        $navOptions += "P (Previous page)"
    }
    if ($currentPage -lt ($totalPages - 1)) {
        $navOptions += "N (Next page)"
    }
    $navOptions += "ESC (Back)"
    $navOptions += "Q (Quit)"

    Write-Host "Navigation: $($navOptions -join " | ")" -ForegroundColor Green
    Write-Host ""

    $userInput = Read-Host "Enter image number or command (P/N/ESC/Q)"

    # Check if input is a number
    if ([int]::TryParse($userInput, [ref]$null)) {
        $selectedNumber = [int]$userInput

        # Validate selection is within range
        if ($selectedNumber -ge 1 -and $selectedNumber -le $sortedImages.Count) {
            $selectedImage = $sortedImages[$selectedNumber - 1]
            break
        }
        else {
            Write-Host "Invalid selection. Please enter a number between 1 and $($sortedImages.Count)." -ForegroundColor Red
            Read-Host "Press Enter to continue"
            Clear-Host
        }
    }
    elseif ($userInput.ToUpper() -eq "P") {
        if ($currentPage -gt 0) {
            $currentPage--
            Clear-Host
        }
        else {
            Write-Host "Already on the first page." -ForegroundColor Yellow
            Read-Host "Press Enter to continue"
            Clear-Host
        }
    }
    elseif ($userInput.ToUpper() -eq "N") {
        if ($currentPage -lt ($totalPages - 1)) {
            $currentPage++
            Clear-Host
        }
        else {
            Write-Host "Already on the last page." -ForegroundColor Yellow
            Read-Host "Press Enter to continue"
            Clear-Host
        }
    }
    elseif ($userInput.ToUpper() -eq "ESC" -or [int]$userInput -eq 27) {
        Write-Host "Going back..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500
        exit 0
    }
    elseif ($userInput.ToUpper() -eq "Q") {
        Write-Host "Exiting Docker Image Explorer." -ForegroundColor Yellow
        exit 0
    }
    else {
        Write-Host "Invalid input. Please enter a number, P (Previous), N (Next), ESC (Back), or Q (Quit)." -ForegroundColor Red
        Read-Host "Press Enter to continue"
        Clear-Host
    }
}

# Launch dive with the selected image
if ($selectedImage) {
    $imageFullName = "{0}:{1}" -f $selectedImage.Repository, $selectedImage.Tag
    Write-Host "Launching dive for: $imageFullName" -ForegroundColor Green
    Write-Host ""

    try {
        & dive $imageFullName
    }
    catch {
        Write-Host "Error launching dive: $_" -ForegroundColor Red
        exit 1
    }
}
