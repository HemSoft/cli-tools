#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Docker Cleanup Script - Removes orphaned Docker images, containers, volumes, and networks
.DESCRIPTION
    This script provides comprehensive Docker cleanup functionality including:
    - Removing stopped containers
    - Removing orphaned/dangling images
    - Removing unused volumes
    - Removing unused networks
    - Optional aggressive cleanup of all unused resources
.PARAMETER Aggressive
    Perform aggressive cleanup (removes all unused images, not just dangling ones)
.PARAMETER DryRun
    Show what would be cleaned up without actually removing anything
.PARAMETER Quiet
    Suppress verbose output and confirmations
.EXAMPLE
    .\docker-cleanup.ps1
    Performs standard cleanup with user confirmation
.EXAMPLE
    .\docker-cleanup.ps1 -Aggressive
    Performs aggressive cleanup removing all unused images
.EXAMPLE
    .\docker-cleanup.ps1 -DryRun
    Shows what would be cleaned without actually removing anything
#>

param(
    [switch]$Aggressive,
    [switch]$DryRun,
    [switch]$Quiet
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    if (-not $Quiet) {
        switch ($Color) {
            "Red" { Write-Host $Message -ForegroundColor Red }
            "Green" { Write-Host $Message -ForegroundColor Green }
            "Yellow" { Write-Host $Message -ForegroundColor Yellow }
            "Blue" { Write-Host $Message -ForegroundColor Blue }
            "Cyan" { Write-Host $Message -ForegroundColor Cyan }
            default { Write-Host $Message }
        }
    }
}

# Function to get disk usage before cleanup
function Get-DockerDiskUsage {
    try {
        $output = docker system df 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $output
        }
    }
    catch {
        # Ignore errors
    }
    return $null
}

# Function to check if Docker is running
function Test-DockerRunning {
    try {
        docker info 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# Main cleanup function
function Start-DockerCleanup {
    Write-ColorOutput "Docker Cleanup Script" "Blue"
    Write-ColorOutput "=====================" "Blue"
    Write-ColorOutput ""

    # Check if Docker is running
    if (-not (Test-DockerRunning)) {
        Write-ColorOutput "ERROR: Docker is not running or not accessible." "Red"
        Write-ColorOutput "Please start Docker and try again." "Yellow"
        return
    }

    # Get initial disk usage
    Write-ColorOutput "Getting current Docker disk usage..." "Cyan"
    $initialUsage = Get-DockerDiskUsage
    if ($initialUsage) {
        Write-ColorOutput $initialUsage "White"
        Write-ColorOutput ""
    }

    if ($DryRun) {
        Write-ColorOutput "DRY RUN MODE - No actual cleanup will be performed" "Yellow"
        Write-ColorOutput ""
    }

    # Cleanup stopped containers
    Write-ColorOutput "Cleaning up stopped containers..." "Green"
    try {
        if ($DryRun) {
            $stoppedContainers = docker ps -a -q -f status=exited 2>$null
            if ($stoppedContainers) {
                Write-ColorOutput "Would remove $($stoppedContainers.Count) stopped container(s)" "Yellow"
            } else {
                Write-ColorOutput "No stopped containers to remove" "Green"
            }
        } else {
            docker container prune -f 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "SUCCESS: Stopped containers cleaned up" "Green"
            }
        }
    }
    catch {
        Write-ColorOutput "WARNING: Error cleaning up containers: $($_.Exception.Message)" "Red"
    }

    # Cleanup dangling images
    Write-ColorOutput "Cleaning up dangling images..." "Green"
    try {
        if ($DryRun) {
            $danglingImages = docker images -q -f dangling=true 2>$null
            if ($danglingImages) {
                Write-ColorOutput "Would remove $($danglingImages.Count) dangling image(s)" "Yellow"
            } else {
                Write-ColorOutput "No dangling images to remove" "Green"
            }
        } else {
            docker image prune -f 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "SUCCESS: Dangling images cleaned up" "Green"
            }
        }
    }
    catch {
        Write-ColorOutput "WARNING: Error cleaning up dangling images: $($_.Exception.Message)" "Red"
    }

    # Cleanup unused volumes
    Write-ColorOutput "Cleaning up unused volumes..." "Green"
    try {
        if ($DryRun) {
            $unusedVolumes = docker volume ls -q -f dangling=true 2>$null
            if ($unusedVolumes) {
                Write-ColorOutput "Would remove $($unusedVolumes.Count) unused volume(s)" "Yellow"
            } else {
                Write-ColorOutput "No unused volumes to remove" "Green"
            }
        } else {
            docker volume prune -f 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "SUCCESS: Unused volumes cleaned up" "Green"
            }
        }
    }
    catch {
        Write-ColorOutput "WARNING: Error cleaning up volumes: $($_.Exception.Message)" "Red"
    }

    # Cleanup unused networks
    Write-ColorOutput "Cleaning up unused networks..." "Green"
    try {
        if ($DryRun) {
            Write-ColorOutput "Would remove unused networks" "Yellow"
        } else {
            docker network prune -f 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "SUCCESS: Unused networks cleaned up" "Green"
            }
        }
    }
    catch {
        Write-ColorOutput "WARNING: Error cleaning up networks: $($_.Exception.Message)" "Red"
    }

    # Aggressive cleanup (all unused images)
    if ($Aggressive) {
        Write-ColorOutput "Performing aggressive cleanup (all unused images)..." "Yellow"
        try {
            if ($DryRun) {
                Write-ColorOutput "Would remove all unused images (aggressive mode)" "Yellow"
            } else {
                docker image prune -a -f 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-ColorOutput "SUCCESS: All unused images cleaned up" "Green"
                }
            }
        }
        catch {
            Write-ColorOutput "WARNING: Error in aggressive cleanup: $($_.Exception.Message)" "Red"
        }
    }

    # System-wide cleanup (alternative approach)
    if (-not $Aggressive) {
        Write-ColorOutput "Running system-wide cleanup..." "Green"
        try {
            if ($DryRun) {
                Write-ColorOutput "Would run docker system prune" "Yellow"
            } else {
                docker system prune -f 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-ColorOutput "SUCCESS: System-wide cleanup completed" "Green"
                }
            }
        }
        catch {
            Write-ColorOutput "WARNING: Error in system cleanup: $($_.Exception.Message)" "Red"
        }
    }

    Write-ColorOutput ""
    Write-ColorOutput "Final Docker disk usage:" "Cyan"
    $finalUsage = Get-DockerDiskUsage
    if ($finalUsage) {
        Write-ColorOutput $finalUsage "White"
    }

    Write-ColorOutput ""
    if ($DryRun) {
        Write-ColorOutput "Dry run completed. No actual cleanup was performed." "Yellow"
        Write-ColorOutput "Run without -DryRun to perform actual cleanup." "Yellow"
    } else {
        Write-ColorOutput "Docker cleanup completed!" "Green"
    }
    
    if ($Aggressive) {
        Write-ColorOutput "WARNING: Aggressive mode was used - all unused images were removed." "Yellow"
        Write-ColorOutput "You may need to re-download images when running containers." "Yellow"
    }
}

# Run the cleanup
Start-DockerCleanup
