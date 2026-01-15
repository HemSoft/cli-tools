# cm.ps1
# Version: 1.2.0 - Added Bearer token authentication for EggCoop API

param(
    [string]$ApiUrl = "https://eggcoop.org/api/contracts",
    [string]$PageSize = "20",
    [string]$SortField = "startTime,desc",
    [string]$Formula = "Majeggstics 24h",
    [string]$TimeSlot = "2 - Two",
    [string]$CoopFlag = "Any Grade",
    [string]$Hidden = "False",
    [switch]$Debug = $false
)

function Write-DebugOutput {
    param([string]$Message)
    if ($Debug) { Write-Output $Message }
}

Write-DebugOutput "Using the following parameters:"
Write-DebugOutput "  API URL: $ApiUrl"
Write-DebugOutput "  Page Size: $PageSize"
Write-DebugOutput "  Sort Field: $SortField"
Write-DebugOutput "  Formula: $Formula"
Write-DebugOutput "  Time Slot: $TimeSlot"
Write-DebugOutput "  Coop Flag: $CoopFlag"
Write-DebugOutput "  Hidden: $Hidden"
Write-DebugOutput ""

function Convert-UTCToLocal {
    param([string]$utcDateStr)
    $utcDate = [DateTime]::Parse($utcDateStr)
    return $utcDate.ToLocalTime()
}

function Get-ScheduledTimeWithDST {
    param(
        [DateTime]$scheduleDate,
        [int]$minuteOffset = 0
    )

    $isDST = [System.TimeZoneInfo]::Local.IsDaylightSavingTime($scheduleDate)

    if ($isDST) {
        # During DST (EDT): 6 PM EST = 7 PM EDT
        $hour = 19
        $offset = "-04:00"
    }
    else {
        # During standard time (EST): 6 PM EST
        $hour = 18
        $offset = "-05:00"
    }

    $time = "{0:D2}:{1:D2}:00" -f $hour, $minuteOffset

    return @{
        Time   = $time
        Offset = $offset
    }
}

function Get-NextDayLocal {
    param([DateTime]$date)
    return $date.AddDays(1).ToString("yyyy-MM-dd")
}

$fullApiUrl = "$ApiUrl`?page=0&size=$PageSize&sort=$SortField"

# Check for API token
$apiToken = $env:EGGCOOP_API_TOKEN
if (-not $apiToken) {
    Write-Output "ERROR: EGGCOOP_API_TOKEN environment variable not found."
    Write-Output ""
    Write-Output "The EggCoop API requires authentication. Please:"
    Write-Output "  1. Login to https://eggcoop.org using Discord"
    Write-Output "  2. Generate an API access token from your profile"
    Write-Output "  3. Set the environment variable:"
    Write-Output "     [Environment]::SetEnvironmentVariable('EGGCOOP_API_TOKEN', 'your-token-here', 'User')"
    Write-Output ""
    exit 1
}

$headers = @{
    'Authorization' = "Bearer $apiToken"
}

try {
    Write-DebugOutput "Fetching contracts from $fullApiUrl..."
    Write-Host "Fetching contracts v1.2.0 (with auth) ..."
    $response = Invoke-RestMethod -Uri $fullApiUrl -Method Get -Headers $headers -TimeoutSec 30
}
catch {
    Write-Output "Failed to fetch contracts from the API."
    Write-Output "Error: $($_.Exception.Message)"
    Write-Output ""
    Write-Output "This could be due to:"
    Write-Output "  - Invalid or expired API token"
    Write-Output "  - Network connectivity issues"
    Write-Output "  - The eggcoop.org API being temporarily unavailable"
    Write-Output "  - Firewall or proxy restrictions"
    Write-Output ""
    Write-Output "Please check your EGGCOOP_API_TOKEN environment variable and try again."
    exit 1
}

if ($null -eq $response._embedded -or $null -eq $response._embedded.contracts) {
    Write-Error "No contracts found in response"
    exit 1
}

$contracts = @($response._embedded.contracts)

if ($contracts.Count -eq 0) {
    Write-Output "No contracts found"
    exit
}

$todayLocal = [DateTime]::Now.Date
Write-DebugOutput "Today's date (Local): $($todayLocal.ToString('yyyy-MM-dd'))"

foreach ($contract in $contracts) {
    $utcDateStr = $contract.startTime
    $localDateTime = Convert-UTCToLocal -utcDateStr $utcDateStr
    $contract | Add-Member -MemberType NoteProperty -Name "localDate" -Value $localDateTime.Date -Force
    $contract | Add-Member -MemberType NoteProperty -Name "localDateString" -Value $localDateTime.ToString("yyyy-MM-dd") -Force
}

$contractsByDate = $contracts | Group-Object -Property localDateString
$sortedDates = $contractsByDate | Sort-Object -Property Name -Descending

Write-DebugOutput "Available contract dates (Local time):"
foreach ($dateGroup in $sortedDates) {
    Write-DebugOutput "  $($dateGroup.Name): $($dateGroup.Count) contract(s)"
}

$todayDateString = $todayLocal.ToString("yyyy-MM-dd")
$todayContracts = @($contracts | Where-Object { $_.localDateString -eq $todayDateString })
Write-DebugOutput "Found $($todayContracts.Count) contracts for today (local time)"

if ($todayContracts.Count -eq 0 -and $sortedDates.Count -gt 0) {
    $mostRecentDate = $sortedDates[0].Name
    $todayContracts = @($contracts | Where-Object { $_.localDateString -eq $mostRecentDate })

    $mostRecentDateTime = [DateTime]::ParseExact($mostRecentDate, "yyyy-MM-dd", $null)
    $daysDifference = ($todayLocal - $mostRecentDateTime).Days

    if ($daysDifference -eq 1) {
        Write-Host "Using contracts from yesterday ($mostRecentDate)"
    }
    else {
        Write-Host "Using contracts from $daysDifference days ago ($mostRecentDate)"
    }
}

# Generate the commands
$commandLines = @()

if ($todayContracts.Count -ge 1) {
    $sortedContracts = $todayContracts | Sort-Object -Property startTime

    Write-DebugOutput "`nGenerating commands for the following contracts:"
    for ($i = 0; $i -lt [Math]::Min($sortedContracts.Count, 2); $i++) {
        $contract = $sortedContracts[$i]
        Write-DebugOutput "  Contract $($i+1): ID=$($contract.contractIdentifier), Date=$($contract.localDateString)"
    }
    Write-DebugOutput ""

    # First command (minute 0)
    $nextDay1 = Get-NextDayLocal -date $sortedContracts[0].localDate
    $scheduleDate1 = [DateTime]::ParseExact($nextDay1, "yyyy-MM-dd", $null)
    $timeInfo1 = Get-ScheduledTimeWithDST -scheduleDate $scheduleDate1 -minuteOffset 0

    $cmd1 = "/checkminimums kevid:$($sortedContracts[0].contractIdentifier) formula:$Formula timeslot:$TimeSlot coopflag:$CoopFlag hidden:$Hidden delay_until:${nextDay1}T$($timeInfo1.Time)$($timeInfo1.Offset)"
    $commandLines += $cmd1

    # Second command (minute 1 - staggered by 1 minute)
    if ($sortedContracts.Count -ge 2) {
        $nextDay2 = Get-NextDayLocal -date $sortedContracts[1].localDate
        $scheduleDate2 = [DateTime]::ParseExact($nextDay2, "yyyy-MM-dd", $null)
        $timeInfo2 = Get-ScheduledTimeWithDST -scheduleDate $scheduleDate2 -minuteOffset 1

        $cmd2 = "/checkminimums kevid:$($sortedContracts[1].contractIdentifier) formula:$Formula timeslot:$TimeSlot coopflag:$CoopFlag hidden:$Hidden delay_until:${nextDay2}T$($timeInfo2.Time)$($timeInfo2.Offset)"
        $commandLines += $cmd2
    }
    elseif ($sortedContracts.Count -eq 1 -and $Debug) {
        Write-Host "`nNote: Only one contract found for the selected date."
    }

    # Output commands
    $commandLines | ForEach-Object { Write-Output $_ }

    # Copy to clipboard
    $clipboardText = $commandLines -join "`n"
    Set-Clipboard -Value $clipboardText
    Write-Host "`n[Copied to clipboard]" -ForegroundColor Green
}
else {
    Write-Output "No contracts found for today or any recent date"
}