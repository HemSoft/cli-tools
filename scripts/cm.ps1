# get-contract-commands.ps1

# Define parameters with default values that can be overridden from configuration
param(
    [string]$ApiUrl = "https://eggcoop.org/api/contracts",
    [string]$PageSize = "20",
    [string]$SortField = "startTime,desc",
    [string]$TimeZoneOffset = "-05:00",
    [string]$Formula = "Majeggstics 24h",
    [string]$TimeSlot = "2 - Two",
    [string]$CoopFlag = "Any Grade",
    [string]$Hidden = "False",
    [switch]$Debug = $false
)

# Function to write debug output only when Debug is enabled
function Write-DebugOutput {
    param([string]$Message)

    if ($Debug) {
        Write-Output $Message
    }
}

# Display the parameters being used (only in debug mode)
Write-DebugOutput "Using the following parameters:"
Write-DebugOutput "  API URL: $ApiUrl"
Write-DebugOutput "  Page Size: $PageSize"
Write-DebugOutput "  Sort Field: $SortField"
Write-DebugOutput "  Time Zone Offset: $TimeZoneOffset"
Write-DebugOutput "  Formula: $Formula"
Write-DebugOutput "  Time Slot: $TimeSlot"
Write-DebugOutput "  Coop Flag: $CoopFlag"
Write-DebugOutput "  Hidden: $Hidden"
Write-DebugOutput ""

# Function to convert UTC time to local time
function Convert-UTCToLocal {
    param([string]$utcDateStr)

    # Parse the UTC date string
    $utcDate = [DateTime]::Parse($utcDateStr)

    # Convert to local time
    $localDate = $utcDate.ToLocalTime()

    return $localDate
}

# Function to get next day in local time for a given date
function Get-NextDayLocal {
    param([DateTime]$date)

    # Add one day to the date
    $nextDay = $date.AddDays(1)

    # Return formatted date string
    return $nextDay.ToString("yyyy-MM-dd")
}

# Construct the full API URL with query parameters
$fullApiUrl = "$ApiUrl`?page=0&size=$PageSize&sort=$SortField"

# Fetch the contracts from the API
try {
    Write-DebugOutput "Fetching contracts from $fullApiUrl..."
    Write-Output "Fetching contracts..."
    $response = Invoke-RestMethod -Uri $fullApiUrl -Method Get -TimeoutSec 30
}
catch {
    Write-Output "Failed to fetch contracts from the API."
    Write-Output "Error: $($_.Exception.Message)"
    Write-Output ""
    Write-Output "This could be due to:"
    Write-Output "  - Network connectivity issues"
    Write-Output "  - The eggcoop.org API being temporarily unavailable"
    Write-Output "  - Firewall or proxy restrictions"
    Write-Output ""
    Write-Output "Please try again later or check your network connection."
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

# For testing: Uncomment to simulate a specific date
# $todayLocal = [DateTime]::ParseExact("2025-05-16", "yyyy-MM-dd", $null)
# Write-Output "Simulating date (Local): $($todayLocal.ToString('yyyy-MM-dd'))"

# Get today's date in local time
$todayLocal = [DateTime]::Now.Date
Write-DebugOutput "Today's date (Local): $($todayLocal.ToString('yyyy-MM-dd'))"

# Process contracts to add local date information
foreach ($contract in $contracts) {
    # Extract date part from startTime
    $utcDateStr = $contract.startTime

    # Convert to local DateTime
    $localDateTime = Convert-UTCToLocal -utcDateStr $utcDateStr

    # Add local date information to contract
    $contract | Add-Member -MemberType NoteProperty -Name "localDate" -Value $localDateTime.Date -Force
    $contract | Add-Member -MemberType NoteProperty -Name "localDateString" -Value $localDateTime.ToString("yyyy-MM-dd") -Force
}

# Group contracts by local date
$contractsByDate = $contracts | Group-Object -Property localDateString

# Sort dates in descending order (most recent first)
$sortedDates = $contractsByDate | Sort-Object -Property Name -Descending

# Display available dates (only in debug mode)
Write-DebugOutput "Available contract dates (Local time):"
foreach ($dateGroup in $sortedDates) {
    Write-DebugOutput "  $($dateGroup.Name): $($dateGroup.Count) contract(s)"
}

# Filter contracts for today
$todayDateString = $todayLocal.ToString("yyyy-MM-dd")
$todayContracts = @($contracts | Where-Object { $_.localDateString -eq $todayDateString })
Write-DebugOutput "Found $($todayContracts.Count) contracts for today (local time)"

# If no contracts for today, use the most recent date with contracts
if ($todayContracts.Count -eq 0 -and $sortedDates.Count -gt 0) {
    $mostRecentDate = $sortedDates[0].Name
    $todayContracts = @($contracts | Where-Object { $_.localDateString -eq $mostRecentDate })

    # Calculate days difference between today and most recent contract date
    $mostRecentDateTime = [DateTime]::ParseExact($mostRecentDate, "yyyy-MM-dd", $null)
    $daysDifference = ($todayLocal - $mostRecentDateTime).Days

    if ($daysDifference -eq 1) {
        Write-Output "Using contracts from yesterday ($mostRecentDate)"
    }
    else {
        Write-Output "Using contracts from $daysDifference days ago ($mostRecentDate)"
    }
}

# Generate the commands
if ($todayContracts.Count -ge 1) {
    # Sort contracts by startTime if there are multiple
    $sortedContracts = $todayContracts | Sort-Object -Property startTime

    # Display the contracts we're using (only in debug mode)
    Write-DebugOutput "`nGenerating commands for the following contracts:"
    for ($i = 0; $i -lt [Math]::Min($sortedContracts.Count, 2); $i++) {
        $contract = $sortedContracts[$i]
        Write-DebugOutput "  Contract $($i+1): ID=$($contract.contractIdentifier), Date=$($contract.localDateString)"
    }
    Write-DebugOutput ""

    # Calculate next day based on first contract's local date
    $nextDay1 = Get-NextDayLocal -date $sortedContracts[0].localDate

    # First command (always present if there are any contracts)
    Write-Output "/checkminimums kevid:$($sortedContracts[0].contractIdentifier) formula:$Formula timeslot:$TimeSlot coopflag:$CoopFlag hidden:$Hidden delay_until:${nextDay1}T17:00:00$TimeZoneOffset"

    # Second command (only if there are at least 2 contracts)
    if ($sortedContracts.Count -ge 2) {
        # Calculate next day based on second contract's local date
        $nextDay2 = Get-NextDayLocal -date $sortedContracts[1].localDate
        Write-Output "/checkminimums kevid:$($sortedContracts[1].contractIdentifier) formula:$Formula timeslot:$TimeSlot coopflag:$CoopFlag hidden:$Hidden delay_until:${nextDay2}T17:01:00$TimeZoneOffset"
    }
    elseif ($sortedContracts.Count -eq 1 -and $Debug) {
        Write-Output "`nNote: Only one contract found for the selected date."
    }
}
else {
    Write-Output "No contracts found for today or any recent date"
}
