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

    try {
        # Get port mappings using simpler approach
        $portMappings = docker inspect --format="{{json .HostConfig.PortBindings}}" $name | ConvertFrom-Json

        # Get environment variables
        $envVars = docker inspect --format="{{json .Config.Env}}" $name | ConvertFrom-Json

        # Get volume mounts
        $mounts = docker inspect --format="{{json .Mounts}}" $name | ConvertFrom-Json

        # Get restart policy
        $restartPolicy = docker inspect --format="{{.HostConfig.RestartPolicy.Name}}" $name

        # Get exposed ports
        $exposedPorts = docker inspect --format="{{json .Config.ExposedPorts}}" $name | ConvertFrom-Json

        return @{
            PortBindings  = $portMappings
            Environment   = $envVars
            Mounts        = $mounts
            RestartPolicy = $restartPolicy
            ExposedPorts  = $exposedPorts
        }
    }
    catch {
        Write-Host "Warning: Could not retrieve full container configuration: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Function to build docker run command from configuration
function Build-DockerRunCommand {
    param (
        [string]$containerName,
        [string]$imageName,
        [hashtable]$config
    )

    $runArgs = @()
    $runArgs += "-d"
    $runArgs += "--name $containerName"

    # Add restart policy
    if ($config.RestartPolicy -and $config.RestartPolicy -ne "no") {
        $runArgs += "--restart $($config.RestartPolicy)"
    }
    else {
        $runArgs += "--restart always"
    }

    # Add port mappings
    if ($config.PortBindings) {
        foreach ($containerPort in $config.PortBindings.PSObject.Properties.Name) {
            $hostBindings = $config.PortBindings.$containerPort
            if ($hostBindings -and $hostBindings.Count -gt 0) {
                foreach ($binding in $hostBindings) {
                    $hostIp = if ($binding.HostIp) { $binding.HostIp } else { "" }
                    $hostPort = $binding.HostPort
                    if ($hostIp) {
                        $runArgs += "-p ${hostIp}:${hostPort}:$($containerPort -replace '/tcp|/udp', '')"
                    }
                    else {
                        $runArgs += "-p ${hostPort}:$($containerPort -replace '/tcp|/udp', '')"
                    }
                }
            }
        }
    }

    # Add volume mounts
    if ($config.Mounts) {
        foreach ($mount in $config.Mounts) {
            if ($mount.Type -eq "volume") {
                $runArgs += "-v $($mount.Name):$($mount.Destination)"
            }
            elseif ($mount.Type -eq "bind") {
                $runArgs += "-v `"$($mount.Source)`":$($mount.Destination)"
            }
        }
    }

    # Add environment variables (filter out standard Docker env vars)
    if ($config.Environment) {
        $standardEnvVars = @("PATH", "HOSTNAME", "HOME")
        foreach ($env in $config.Environment) {
            $envName = $env.Split('=')[0]
            if ($envName -notin $standardEnvVars -and -not $envName.StartsWith("DOCKER_")) {
                $runArgs += "-e `"$env`""
            }
        }
    }

    # Add image name
    $runArgs += $imageName

    return "docker run $($runArgs -join ' ')"
}
# Step 1: Check if container exists and get configuration if it does
$containerExists = Test-ContainerExists -name $containerName
$currentConfig = $null

if ($containerExists) {
    Write-Host "Found existing container '$containerName'" -ForegroundColor Green

    # Step 2: Get current configuration before updating
    $currentConfig = Get-ContainerConfig -name $containerName

    if ($currentConfig) {
        Write-Host "Successfully retrieved container configuration" -ForegroundColor Green

        # Display current configuration summary
        Write-Host "`nCurrent Configuration Summary:" -ForegroundColor Cyan

        # Show port mappings
        if ($currentConfig.PortBindings -and $currentConfig.PortBindings.PSObject.Properties.Count -gt 0) {
            Write-Host "Port Mappings:" -ForegroundColor Yellow
            foreach ($containerPort in $currentConfig.PortBindings.PSObject.Properties.Name) {
                $hostBindings = $currentConfig.PortBindings.$containerPort
                if ($hostBindings -and $hostBindings.Count -gt 0) {
                    foreach ($binding in $hostBindings) {
                        $hostPort = $binding.HostPort
                        $cleanContainerPort = $containerPort -replace '/tcp|/udp', ''
                        Write-Host "  $hostPort -> $cleanContainerPort" -ForegroundColor White
                    }
                }
            }
        }
        else {
            Write-Host "Port Mappings: None (container not accessible from host)" -ForegroundColor Red
        }

        # Show volumes
        if ($currentConfig.Mounts -and $currentConfig.Mounts.Count -gt 0) {
            Write-Host "Volume Mounts:" -ForegroundColor Yellow
            foreach ($mount in $currentConfig.Mounts) {
                if ($mount.Type -eq "volume") {
                    Write-Host "  Volume: $($mount.Name) -> $($mount.Destination)" -ForegroundColor White
                }
                elseif ($mount.Type -eq "bind") {
                    Write-Host "  Bind: $($mount.Source) -> $($mount.Destination)" -ForegroundColor White
                }
            }
        }
        else {
            Write-Host "Volume Mounts: None" -ForegroundColor White
        }

        Write-Host "Restart Policy: $($currentConfig.RestartPolicy)" -ForegroundColor White
        Write-Host
    }
    else {
        Write-Host "Warning: Could not retrieve container configuration. Will use default settings." -ForegroundColor Yellow
    }

    # Step 3: Stop and remove the existing container
    if (Test-ContainerRunning -name $containerName) {
        Write-Host "Stopping container '$containerName'..." -ForegroundColor Yellow
        docker stop $containerName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to stop container. Exiting." -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "Removing container '$containerName'..." -ForegroundColor Yellow
    docker rm $containerName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to remove container. Exiting." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Container '$containerName' not found. Will create a new container..." -ForegroundColor Yellow
}

# Step 4: Pull the latest image
Write-Host "Pulling the latest OpenWebUI image..." -ForegroundColor Yellow
docker pull $imageName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to pull image. Exiting." -ForegroundColor Red
    exit 1
}

# Step 5: Recreate the container with the same configuration or defaults
Write-Host "Creating a new container with the latest image..." -ForegroundColor Yellow

if ($containerExists -and $currentConfig) {
    # Use the retrieved configuration
    $createCommand = Build-DockerRunCommand -containerName $containerName -imageName $imageName -config $currentConfig
    Write-Host "Using existing configuration..." -ForegroundColor Green
}
else {
    # Create with default settings
    Write-Host "Using default configuration..." -ForegroundColor Yellow

    # Check if the volume exists first
    $volumeExists = docker volume ls --format "{{.Name}}" | Select-String -Pattern "^$volumeName$"

    if ($null -ne $volumeExists) {
        Write-Host "Found existing volume: $volumeName" -ForegroundColor Green
        # Default configuration with volume attachment and proper port mapping
        $createCommand = "docker run -d --name $containerName --restart always -p 3100:8080 -v ${volumeName}:/app/backend/data $imageName"
    }
    else {
        Write-Host "Volume '$volumeName' not found. Creating container with default settings and new volume." -ForegroundColor Yellow
        # Default configuration with proper port mapping
        $createCommand = "docker run -d --name $containerName --restart always -p 3100:8080 -v ${volumeName}:/app/backend/data $imageName"
        Write-Host "Note: A new volume will be created for data persistence." -ForegroundColor Yellow
    }
}

Write-Host "`nRunning command:" -ForegroundColor Gray
Write-Host $createCommand -ForegroundColor White
Write-Host

# Execute the command
Invoke-Expression $createCommand
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create container. Exiting." -ForegroundColor Red
    exit 1
}

# Step 6: Verify the container is running
Write-Host "Waiting for container to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

if (Test-ContainerRunning -name $containerName) {
    Write-Host "✅ OpenWebUI has been successfully updated and is running!" -ForegroundColor Green

    # Display container information
    Write-Host "`nContainer Information:" -ForegroundColor Cyan
    docker ps --filter name=$containerName --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    # Get and display access information
    Write-Host "`nAccess Information:" -ForegroundColor Cyan
    $portInfo = docker inspect --format="{{json .HostConfig.PortBindings}}" $containerName | ConvertFrom-Json

    if ($portInfo -and $portInfo.PSObject.Properties.Count -gt 0) {
        foreach ($containerPort in $portInfo.PSObject.Properties.Name) {
            $hostBindings = $portInfo.$containerPort
            if ($hostBindings -and $hostBindings.Count -gt 0) {
                foreach ($binding in $hostBindings) {
                    $hostPort = $binding.HostPort
                    $cleanContainerPort = $containerPort -replace '/tcp|/udp', ''
                    Write-Host "🌐 OpenWebUI is accessible at: http://localhost:$hostPort" -ForegroundColor Green
                }
            }
        }
    }
    else {
        Write-Host "⚠️  Warning: No port mappings found. Container may not be accessible from host." -ForegroundColor Yellow
        Write-Host "   The container is running but you may need to recreate it with proper port mapping." -ForegroundColor Yellow
    }

    # Show volume information
    Write-Host "`nData Persistence:" -ForegroundColor Cyan
    $mountInfo = docker inspect --format="{{json .Mounts}}" $containerName | ConvertFrom-Json
    if ($mountInfo -and $mountInfo.Count -gt 0) {
        foreach ($mount in $mountInfo) {
            if ($mount.Type -eq "volume") {
                Write-Host "💾 Data volume: $($mount.Name) -> $($mount.Destination)" -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "⚠️  Warning: No persistent volumes found. Data may be lost when container is removed." -ForegroundColor Yellow
    }
}
else {
    Write-Host "❌ Failed to start the updated container." -ForegroundColor Red
    Write-Host "`nChecking container logs for errors:" -ForegroundColor Yellow
    docker logs $containerName --tail 20
    Write-Host "`nTroubleshooting commands:" -ForegroundColor Yellow
    Write-Host "  Check logs: docker logs $containerName" -ForegroundColor White
    Write-Host "  Check status: docker ps -a --filter name=$containerName" -ForegroundColor White
}

Write-Host "`n========================================" -ForegroundColor Cyan
