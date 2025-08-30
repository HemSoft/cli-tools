# Update-n8n.ps1
# Script to update n8n Docker container to the latest version while preserving configuration
# Created: Aug 29, 2025

param()

# Configuration defaults (can be overridden by detected values)
$defaultContainerName = "n8n"
$defaultImage = "n8nio/n8n:latest"   # Official Docker Hub image
$altImage = "ghcr.io/n8n-io/n8n:latest" # Alternate GHCR image
$defaultVolume = "n8n_data"            # Common default volume name for n8n

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "            n8n Update Script             " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host

function Find-N8nContainer {
    # Try to find any container that looks like n8n by image or name
    $candidates = docker ps -a --format "{{.ID}} {{.Image}} {{.Names}}"
    if (-not $candidates) { return $null }

    $lines = $candidates -split "`n" | Where-Object { $_.Trim() -ne "" }
    foreach ($line in $lines) {
        $parts = $line -split "\s+", 3
        if ($parts.Count -lt 3) { continue }
        $id = $parts[0]; $img = $parts[1]; $name = $parts[2]
        if ($img -match "(?i)n8n" -or $name -match "(?i)^n8n(-|$)") {
            return @{ ID = $id; Image = $img; Name = $name }
        }
    }
    return $null
}

function Test-ContainerExists {
    param([string]$name)
    $exists = docker ps -a --format "{{.Names}}" | Select-String -Pattern "^$([regex]::Escape($name))$"
    return $null -ne $exists
}

function Test-ContainerRunning {
    param([string]$name)
    $running = docker ps --format "{{.Names}}" | Select-String -Pattern "^$([regex]::Escape($name))$"
    return $null -ne $running
}

function Get-ContainerConfig {
    param([string]$name)
    Write-Host "Retrieving current container configuration..." -ForegroundColor Yellow
    try {
        $portBindings  = docker inspect --format="{{json .HostConfig.PortBindings}}" $name | ConvertFrom-Json
        $envVars       = docker inspect --format="{{json .Config.Env}}" $name | ConvertFrom-Json
        $mounts        = docker inspect --format="{{json .Mounts}}" $name | ConvertFrom-Json
        $restartPolicy = docker inspect --format="{{.HostConfig.RestartPolicy.Name}}" $name
        $image         = docker inspect --format="{{.Config.Image}}" $name
        $networks      = docker inspect --format="{{json .NetworkSettings.Networks}}" $name | ConvertFrom-Json
        return @{
            PortBindings  = $portBindings
            Environment   = $envVars
            Mounts        = $mounts
            RestartPolicy = $restartPolicy
            Image         = $image
            Networks      = $networks
        }
    }
    catch {
        Write-Host "Warning: Could not retrieve full container configuration: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Build-DockerRunCommand {
    param(
        [string]$containerName,
        [string]$imageName,
        [hashtable]$config
    )

    # Build docker run arguments as an array to avoid quoting issues.
    $args = @('run', '-d', '--name', $containerName)

    # Restart policy
    if ($config.RestartPolicy -and $config.RestartPolicy -ne 'no') {
        $args += @('--restart', $config.RestartPolicy)
    }
    else {
        $args += @('--restart', 'always')
    }

    # Network (attach to first network if present)
    if ($config.Networks) {
        $netProps = $config.Networks.PSObject.Properties
        if ($netProps -and $netProps.Count -gt 0) {
            $firstNet = $netProps[0].Name
            if ($firstNet) { $args += @('--network', $firstNet) }
        }
    }

    # Ports
    if ($config.PortBindings) {
        foreach ($containerPort in $config.PortBindings.PSObject.Properties.Name) {
            $hostBindings = $config.PortBindings.$containerPort
            if ($hostBindings) {
                foreach ($binding in $hostBindings) {
                    $hostIp = if ($binding.HostIp) { $binding.HostIp } else { '' }
                    $hostPort = $binding.HostPort
                    $portNo = ($containerPort -replace '/tcp|/udp','')
                    if ($hostIp) { $args += @('-p', "${hostIp}:${hostPort}:$portNo") }
                    else { $args += @('-p', "${hostPort}:$portNo") }
                }
            }
        }
    }

    # Volumes
    if ($config.Mounts) {
        foreach ($m in $config.Mounts) {
            if ($m.Type -eq 'volume') {
                $args += @('-v', "${($m.Name)}:${($m.Destination)}")
            }
            elseif ($m.Type -eq 'bind') {
                # For bind mounts on Windows, quoting isn't needed when passing as array args; keep it simple.
                $args += @('-v', "${($m.Source)}:${($m.Destination)}")
            }
        }
    }

    # Env vars (keep non-docker defaults)
    if ($config.Environment) {
        $standardEnv = @('PATH','HOSTNAME','HOME')
        foreach ($env in $config.Environment) {
            $envName = $env.Split('=')[0]
            if ($envName -notin $standardEnv -and -not $envName.StartsWith('DOCKER_')) {
                $args += @('-e', $env)
            }
        }
    }

    # Image last
    $args += $imageName

    # Build a readable display string for logs
    $display = "docker " + ((
        $args | ForEach-Object {
            if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
        }
    ) -join ' ')

    [PSCustomObject]@{
        Args    = $args
        Display = $display
    }
}

# Step 0: Try to detect an existing container
$detected = Find-N8nContainer
$containerName = if ($detected) { $detected.Name } else { $defaultContainerName }

# Step 1: Determine image to use
$imageToUse = $defaultImage
if ($detected -and $detected.Image) {
    # Keep the same registry/tag family but move to latest tag
    if ($detected.Image -match "(?i)ghcr\.io/n8n-io/n8n") { $imageToUse = $altImage }
    else { $imageToUse = $defaultImage }
}

# Step 2: If container exists, capture current config
$containerExists = Test-ContainerExists -name $containerName
$currentConfig = $null
if ($containerExists) {
    Write-Host "Found existing container '$containerName'" -ForegroundColor Green
    $currentConfig = Get-ContainerConfig -name $containerName

    if ($currentConfig) {
        Write-Host "Successfully retrieved container configuration" -ForegroundColor Green
        Write-Host "`nCurrent Configuration Summary:" -ForegroundColor Cyan
        if ($currentConfig.PortBindings -and $currentConfig.PortBindings.PSObject.Properties.Count -gt 0) {
            Write-Host "Port Mappings:" -ForegroundColor Yellow
            foreach ($cp in $currentConfig.PortBindings.PSObject.Properties.Name) {
                foreach ($b in $currentConfig.PortBindings.$cp) {
                    $hp = $b.HostPort; $cpClean = $cp -replace '/tcp|/udp',''
                    Write-Host "  $hp -> $cpClean" -ForegroundColor White
                }
            }
        } else { Write-Host "Port Mappings: None" -ForegroundColor White }

        if ($currentConfig.Mounts -and $currentConfig.Mounts.Count -gt 0) {
            Write-Host "Volume Mounts:" -ForegroundColor Yellow
            foreach ($m in $currentConfig.Mounts) {
                if ($m.Type -eq "volume") { Write-Host "  Volume: $($m.Name) -> $($m.Destination)" -ForegroundColor White }
                elseif ($m.Type -eq "bind") { Write-Host "  Bind: $($m.Source) -> $($m.Destination)" -ForegroundColor White }
            }
        } else { Write-Host "Volume Mounts: None" -ForegroundColor White }

        Write-Host "Restart Policy: $($currentConfig.RestartPolicy)" -ForegroundColor White
        Write-Host
    } else { Write-Host "Warning: Could not retrieve container configuration. Will use defaults." -ForegroundColor Yellow }

    # Stop & remove
    if (Test-ContainerRunning -name $containerName) {
        Write-Host "Stopping container '$containerName'..." -ForegroundColor Yellow
        docker stop $containerName
        if ($LASTEXITCODE -ne 0) { Write-Host "Failed to stop container. Exiting." -ForegroundColor Red; exit 1 }
    }
    Write-Host "Removing container '$containerName'..." -ForegroundColor Yellow
    docker rm $containerName
    if ($LASTEXITCODE -ne 0) { Write-Host "Failed to remove container. Exiting." -ForegroundColor Red; exit 1 }
}
else {
    Write-Host "Container '$containerName' not found. Will create a new container..." -ForegroundColor Yellow
}

# Step 3: Pull latest image
Write-Host "Pulling the latest n8n image ($imageToUse)..." -ForegroundColor Yellow
docker pull $imageToUse
if ($LASTEXITCODE -ne 0) { Write-Host "Failed to pull image. Exiting." -ForegroundColor Red; exit 1 }

# Step 4: Create container (using existing config or sane defaults)
Write-Host "Creating a new container with the latest image..." -ForegroundColor Yellow

if ($containerExists -and $currentConfig) {
    $createSpec = Build-DockerRunCommand -containerName $containerName -imageName $imageToUse -config $currentConfig
    Write-Host "Using existing configuration..." -ForegroundColor Green
}
else {
    Write-Host "Using default configuration..." -ForegroundColor Yellow
    # Ensure a default volume mapping for persistence
    $volumeExists = docker volume ls --format "{{.Name}}" | Select-String -Pattern "^$([regex]::Escape($defaultVolume))$"
    if ($null -eq $volumeExists) {
        Write-Host "Volume '$defaultVolume' not found. It will be created automatically by Docker." -ForegroundColor Yellow
    }
    # Default: port 5678, data at /home/node/.n8n, restart always
    $args = @('run','-d','--name', $containerName,'--restart','always','-p','5678:5678','-v',"${defaultVolume}:/home/node/.n8n", $imageToUse)
    $display = "docker " + ($args -join ' ')
    $createSpec = [PSCustomObject]@{ Args = $args; Display = $display }
}

Write-Host "`nRunning command:" -ForegroundColor Gray
Write-Host $createSpec.Display -ForegroundColor White
Write-Host

& docker @($createSpec.Args)
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create container. Exiting." -ForegroundColor Red
    exit 1
}

# Step 5: Verify
Write-Host "Waiting for container to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

if (Test-ContainerRunning -name $containerName) {
    Write-Host "✅ n8n has been successfully updated and is running!" -ForegroundColor Green
    Write-Host "`nContainer Information:" -ForegroundColor Cyan
    docker ps --filter name=$containerName --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    Write-Host "`nAccess Information:" -ForegroundColor Cyan
    $portInfo = docker inspect --format="{{json .HostConfig.PortBindings}}" $containerName | ConvertFrom-Json
    if ($portInfo -and $portInfo.PSObject.Properties.Count -gt 0) {
        foreach ($cp in $portInfo.PSObject.Properties.Name) {
            foreach ($b in $portInfo.$cp) {
                $hp = $b.HostPort
                Write-Host "🌐 n8n is accessible at: http://localhost:$hp" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "⚠️  Warning: No port mappings found. Container may not be accessible from host." -ForegroundColor Yellow
    }

    # Show persistence info
    Write-Host "`nData Persistence:" -ForegroundColor Cyan
    $mountInfo = docker inspect --format="{{json .Mounts}}" $containerName | ConvertFrom-Json
    if ($mountInfo) {
        foreach ($m in $mountInfo) {
            if ($m.Type -eq "volume") { Write-Host "💾 Data volume: $($m.Name) -> $($m.Destination)" -ForegroundColor Green }
            elseif ($m.Type -eq "bind") { Write-Host "💾 Bind mount: $($m.Source) -> $($m.Destination)" -ForegroundColor Green }
        }
    }
}
else {
    Write-Host "❌ Failed to start the updated container." -ForegroundColor Red
    Write-Host "`nChecking container logs for errors:" -ForegroundColor Yellow
    docker logs $containerName --tail 50
    Write-Host "`nTroubleshooting commands:" -ForegroundColor Yellow
    Write-Host "  docker logs $containerName" -ForegroundColor White
    Write-Host "  docker ps -a --filter name=$containerName" -ForegroundColor White
}

Write-Host "`n========================================" -ForegroundColor Cyan
