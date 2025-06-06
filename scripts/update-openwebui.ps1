# Update-OpenWebUI.ps1
# Script to update OpenWebUI Docker container
# Created: May 15, 2025

# Configuration - modify these variables as needed
$containerName = "openwebui"
$imageName = "ghcr.io/open-webui/open-webui:main"
$volumeName = "openwebui-data"  # Change this if your volume name is different

# Display banner
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "        OpenWebUI Update Script         " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host

# Function to check if container exists
function Test-ContainerExists {
    param (
        [string]$name
    )
    
    $exists = docker ps -a --format "{{.Names}}" | Select-String -Pattern "^$name$"
    return $null -ne $exists
}

# Function to check if container is running
function Test-ContainerRunning {
    param (
        [string]$name
    )
    
    $running = docker ps --format "{{.Names}}" | Select-String -Pattern "^$name$"
    return $null -ne $running
}

# Function to get current container configuration
function Get-ContainerConfig {
    param (
        [string]$name
    )
    
    Write-Host "Retrieving current container configuration..." -ForegroundColor Yellow
    
    # Get port mappings
    $portMappings = docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{range $conf}}{{.HostIp}}:{{.HostPort}}{{end}}{{"\n"}}{{end}}' $name
    
    # Get environment variables
    $envVars = docker inspect --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $name
    
    # Get all run arguments (this is complex and not fully accurate)
    $runCommand = docker inspect --format='{{range .Config.Env}}-e {{.}} {{end}}{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}-p {{.HostIp}}:{{.HostPort}}:{{$p}} {{end}}{{end}}{{range .Mounts}}{{if eq .Type "volume"}}-v {{.Name}}:{{.Destination}} {{end}}{{end}}' $name
    
    # Get restart policy
    $restartPolicy = docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' $name
    
    return @{
        Ports         = $portMappings
        Environment   = $envVars
        RunCommand    = $runCommand
        RestartPolicy = $restartPolicy
    }
}

# Step 1: Check if container exists and get configuration if it does
$containerExists = Test-ContainerExists -name $containerName
$currentConfig = $null

if ($containerExists) {
    # Step 2: Get current configuration before updating
    $currentConfig = Get-ContainerConfig -name $containerName
    
    # Step 4: Stop and remove the existing container
    if (Test-ContainerRunning -name $containerName) {
        Write-Host "Stopping container '$containerName'..." -ForegroundColor Yellow
        docker stop $containerName
    }

    Write-Host "Removing container '$containerName'..." -ForegroundColor Yellow
    docker rm $containerName
}
else {
    Write-Host "Container '$containerName' not found. Will create a new container connecting to existing volume '$volumeName'..." -ForegroundColor Yellow
}

# Step 3: Pull the latest image
Write-Host "Pulling the latest OpenWebUI image..." -ForegroundColor Yellow
docker pull $imageName

# Step 5: Recreate the container with the same configuration or defaults
Write-Host "Creating a new container with the latest image..." -ForegroundColor Yellow

if ($containerExists -and $currentConfig) {
    # Build the run command based on the current configuration
    $restartFlag = ""
    if ($currentConfig.RestartPolicy -eq "always") {
        $restartFlag = "--restart always"
    }

    # Extract port mappings in a format usable for docker run
    $portMappings = docker inspect --format='{{range $p, $conf := .HostConfig.PortBindings}}{{range $conf}}-p {{.HostPort}}:{{$p}} {{end}}{{end}}' $containerName 2>$null

    # Extract volume mappings
    $volumeMappings = docker inspect --format='{{range .Mounts}}{{if eq .Type "volume"}}-v {{.Name}}:{{.Destination}} {{end}}{{end}}' $containerName 2>$null

    # Extract environment variables
    $envVars = docker inspect --format='{{range .Config.Env}}-e "{{.}}" {{end}}' $containerName 2>$null

    # Create the new container with the extracted configuration
    $createCommand = "docker run -d --name $containerName $restartFlag $portMappings $volumeMappings $envVars $imageName"
}
else {
    # Create with default settings but attach to existing volume
    # Check if the volume exists first
    $volumeExists = $(docker volume ls --format "{{.Name}}" | Select-String -Pattern "^$volumeName$")
    
    if ($null -ne $volumeExists) {
        Write-Host "Found existing volume: $volumeName" -ForegroundColor Green
        # Default configuration with volume attachment
        $createCommand = "docker run -d --name $containerName --restart always -p 3100:8080 -v ${volumeName}:/app/backend/data $imageName"
    }
    else {
        Write-Host "Volume '$volumeName' not found. Creating a new container with default settings." -ForegroundColor Yellow
        # Default configuration without volume
        $createCommand = "docker run -d --name $containerName --restart always -p 3100:8080 $imageName"
        Write-Host "Note: This will create a new container without restoring previous settings." -ForegroundColor Yellow
    }
}

Write-Host "Running command: $createCommand" -ForegroundColor Gray
Invoke-Expression $createCommand

# Step 6: Verify the container is running
Start-Sleep -Seconds 5
if (Test-ContainerRunning -name $containerName) {
    Write-Host "✅ OpenWebUI has been successfully updated and is running!" -ForegroundColor Green
    
    # Display container information
    Write-Host "`nContainer Information:" -ForegroundColor Cyan
    docker ps --filter name=$containerName
}
else {
    Write-Host "❌ Failed to start the updated container. Please check docker logs for details." -ForegroundColor Red
    Write-Host "Command to check logs: docker logs $containerName" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
