# get-contract-commands.ps1

# Fetch the contracts from the API
try {
    $response = Invoke-RestMethod -Uri "https://eggcoop.org/api/contracts?page=0&size=20&sort=startTime,desc" -Method Get
}
catch {
    Write-Error "Failed to fetch contracts: $_"
    exit 1
}

# Get the contracts
if ($null -eq $response._embedded -or $null -eq $response._embedded.contracts) {
    Write-Error "No contracts found in response"
    exit 1
}

$contracts = @($response._embedded.contracts)

# If there are no contracts, exit
if ($contracts.Count -eq 0) {
    Write-Output "No contracts found"
    exit
}

# Get today's date in UTC and format it to match API format
$today = [DateTime]::UtcNow.Date.ToString("yyyy-MM-dd")

# Filter contracts to only include those from today
[array]$todayContracts = @($contracts | Where-Object { $_.startTime.Split('T')[0] -eq $today })

# Function to get next day in CST/CDT for a given date
function Get-NextDayInCST {
    param([string]$dateStr)
    $date = [DateTime]::ParseExact($dateStr, "yyyy-MM-dd", $null)
    $nextDayLocal = $date.AddDays(1)
    return $nextDayLocal.ToString("yyyy-MM-dd")
}

# Generate the commands
if ($todayContracts.Count -ge 1) {
    # Calculate next day based on first contract's start date
    $nextDay1 = Get-NextDayInCST -dateStr $todayContracts[0].startTime.Split('T')[0]
    
    # First command (always present if there are any contracts)
    Write-Output "/checkminimums kevid:$($todayContracts[0].contractIdentifier) formula:Majeggstics 24h timeslot:2 - Two coopflag:Any Grade hidden:False delay_until:${nextDay1}T17:00:00-05:00"
    
    # Second command (only if there are at least 2 contracts)
    if ($todayContracts.Count -ge 2) {
        # Calculate next day based on second contract's start date
        $nextDay2 = Get-NextDayInCST -dateStr $todayContracts[1].startTime.Split('T')[0]
        Write-Output "/checkminimums kevid:$($todayContracts[1].contractIdentifier) formula:Majeggstics 24h timeslot:2 - Two coopflag:Any Grade hidden:False delay_until:${nextDay2}T17:01:00-05:00"
    }
}
else {
    Write-Output "No contracts found for today"
}