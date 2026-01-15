#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unified PR Checker for GitHub and Bitbucket.

.DESCRIPTION
    Checks for Pull Requests across GitHub (using gh CLI) and Bitbucket (using API) based on your involvement.

.PARAMETER ApprovedAndOpen
    List PRs you have approved that are still open.

.PARAMETER ApprovedAndMergedSince
    List PRs you have approved that have been merged since the specified date.

.PARAMETER GitHubOrg
    GitHub Organization to search (default: relias-engineering).

.PARAMETER BitbucketWorkspace
    Bitbucket Workspace to search (default: relias).

.PARAMETER BitbucketUser
    Bitbucket User display name or UUID (default: Franz Hemmer).

.PARAMETER Watch
    Refresh interval in minutes when running in watch mode (default: 15).

.PARAMETER Once
    Run once and exit instead of continuous watch mode.

.PARAMETER Interactive
    Enable interactive PR browser (press 'I' during watch mode to browse PRs).

.PARAMETER SkipBitbucket
    Skip Bitbucket checks (GitHub only).

.EXAMPLE
    .\check-my-prs.ps1 -Once
    List all PRs once and exit.

.EXAMPLE
    .\check-my-prs.ps1
    Run in watch mode, refreshing every 15 minutes.

.EXAMPLE
    .\check-my-prs.ps1 -ApprovedAndOpen
    List PRs you've approved that are still open.
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'ApprovedAndOpen')]
    [switch]$ApprovedAndOpen,

    [Parameter(ParameterSetName = 'ApprovedAndMergedSince')]
    [DateTime]$ApprovedAndMergedSince,

    [string]$GitHubOrg = 'relias-engineering',
    [string]$BitbucketWorkspace = 'relias',
    [string]$BitbucketUser = 'Franz Hemmer',
    [int]$Watch = 15,
    [switch]$Once,
    [switch]$SkipBitbucket,
    [switch]$Help
)

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

# Check for and install PwshSpectreConsole if not available
if (-not (Get-Module -ListAvailable -Name PwshSpectreConsole)) {
    Write-Host "Installing PwshSpectreConsole module for better UI..." -ForegroundColor Yellow
    Install-Module -Name PwshSpectreConsole -Scope CurrentUser -Force -AllowClobber
}
Import-Module PwshSpectreConsole

# Auto-load User environment variables if not present in session
# (Handles VS Code terminals that don't inherit updated User env vars)
if (-not $env:BITBUCKET_API_KEY) {
    $env:BITBUCKET_API_KEY = [System.Environment]::GetEnvironmentVariable('BITBUCKET_API_KEY', 'User')
}
if (-not $env:BITBUCKET_USERNAME) {
    $env:BITBUCKET_USERNAME = [System.Environment]::GetEnvironmentVariable('BITBUCKET_USERNAME', 'User')
}

# Determine Mode
$mode = 'Default'
if ($PSCmdlet.ParameterSetName -eq 'ApprovedAndOpen') { $mode = 'ApprovedAndOpen' }
if ($PSCmdlet.ParameterSetName -eq 'ApprovedAndMergedSince') { $mode = 'ApprovedAndMergedSince' }

# -----------------------------------------------------------------------------
# GitHub Job Logic
# -----------------------------------------------------------------------------
$sbGitHub = {
    param($Org, $Mode, $DateStr)

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return @() }

    # Get current user login
    $currentUser = gh api user --jq .login 2>$null

    $allPrs = @()
    $seenUrls = @{}

    # Helper function to fetch PR details including reviews and assignees
    function Get-PrDetails {
        param($PrUrl)
        $detailsJson = gh pr view $PrUrl --json number,title,url,state,mergedAt,createdAt,author,reviews,assignees 2>$null
        if ($LASTEXITCODE -eq 0 -and $detailsJson) {
            return $detailsJson | ConvertFrom-Json
        }
        return $null
    }

    # Use gh search prs which works reliably with assignee/reviewed-by/author filters
    # Unlike gh pr list --search, these actually return correct results
    $searchCommands = @()

    if ($Mode -eq 'ApprovedAndOpen') {
        # PRs I reviewed that are approved and still open
        $searchCommands += @{ Args = @('--reviewed-by=@me', '--state=open', "--owner=$Org") }
    }
    elseif ($Mode -eq 'ApprovedAndMergedSince') {
        # PRs I reviewed that were merged since the date
        $searchCommands += @{ Args = @('--reviewed-by=@me', '--state=merged', "--owner=$Org", "--merged=>=$DateStr") }
    }
    else {
        # Default mode: PRs I authored, am assigned to, have reviewed, or am requested to review
        $searchCommands += @{ Args = @('--author=@me', '--state=open', "--owner=$Org") }
        $searchCommands += @{ Args = @('--assignee=@me', '--state=open', "--owner=$Org") }
        $searchCommands += @{ Args = @('--reviewed-by=@me', '--state=open', "--owner=$Org") }
        $searchCommands += @{ Args = @('--review-requested=@me', '--state=open', "--owner=$Org") }
    }

    foreach ($cmd in $searchCommands) {
        $args = @('search', 'prs') + $cmd.Args + @('--json', 'number,title,url,repository', '--limit', '100')
        $ghOutput = & gh @args 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "GitHub CLI error: $ghOutput"
            continue
        }

        try {
            $searchResults = $ghOutput | ConvertFrom-Json
        } catch {
            if ([string]::IsNullOrWhiteSpace($ghOutput)) { continue }
            Write-Error "Failed to parse GitHub JSON: $_"
            continue
        }

        if ($searchResults) {
            if ($searchResults -isnot [array]) { $searchResults = @($searchResults) }
            foreach ($result in $searchResults) {
                if (-not $seenUrls.ContainsKey($result.url)) {
                    $seenUrls[$result.url] = $true
                    # Fetch full PR details to get reviews
                    $prDetails = Get-PrDetails -PrUrl $result.url
                    if ($prDetails) {
                        $allPrs += $prDetails
                    }
                }
            }
        }
    }

    if (-not $allPrs) { return @() }

    return $allPrs | ForEach-Object {
        $repoName = ($_.url -split '/')[-3]

        # Count unique approvals and check if current user approved
        $approvalCount = 0
        $iApproved = $false
        if ($_.reviews) {
            $reviewerGroups = $_.reviews | Group-Object { $_.author.login }
            foreach ($group in $reviewerGroups) {
                $latestReview = $group.Group | Sort-Object submittedAt -Descending | Select-Object -First 1
                if ($latestReview.state -eq 'APPROVED') {
                    $approvalCount++
                    if ($latestReview.author.login -eq $currentUser) { $iApproved = $true }
                }
            }
        }

        # Count assignees
        $assigneeCount = if ($_.assignees) { $_.assignees.Count } else { 0 }

        [PSCustomObject]@{
            Source        = "GitHub"
            Repository    = $repoName
            ID            = $_.number
            Title         = $_.title
            Author        = $_.author.login
            URL           = $_.url
            State         = $_.state
            ApprovalCount = $approvalCount
            AssigneeCount = $assigneeCount
            IApproved     = $iApproved
            Created       = if ($_.createdAt) { Get-Date $_.createdAt } else { $null }
            Date          = if ($_.mergedAt) { $_.mergedAt } else { $null }
        }
    }
}

# -----------------------------------------------------------------------------
# Bitbucket Job Logic
# -----------------------------------------------------------------------------
$sbBitbucket = {
    param($Workspace, $Mode, $DateStr, $Token, $Username)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Warning "BITBUCKET_API_KEY is missing. Skipping Bitbucket checks."
        return @()
    }

    function Invoke-BitbucketApi {
        param($Uri, $Headers)
        $attempt = 0
        $maxAttempts = 5
        while ($attempt -lt $maxAttempts) {
            $attempt++
            try {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -ErrorAction Stop
            }
            catch {
                $ex = $_.Exception
                # Check for 429 Too Many Requests
                if ($ex.Response -and [int]$ex.Response.StatusCode -eq 429) {
                    $retryAfter = 60
                    if ($ex.Response.Headers["Retry-After"]) {
                        $retryAfter = [int]$ex.Response.Headers["Retry-After"]
                    }
                    # Add a bit of jitter
                    $retryAfter += (Get-Random -Minimum 1 -Maximum 5)

                    if ($attempt -lt $maxAttempts) {
                        Start-Sleep -Seconds $retryAfter
                        continue
                    }
                }
                # If not 429 or retries exhausted, rethrow
                throw $_
            }
        }
    }

    function Get-BitbucketPagedResult {
        param($Uri, $Headers)
        $results = @()
        $nextUri = $Uri

        do {
            $resp = Invoke-BitbucketApi -Uri $nextUri -Headers $Headers
            if ($resp.values) {
                $results += $resp.values
            }
            $nextUri = $resp.next
        } while ($nextUri)

        return $results
    }

    # Auth Header
    $authHeader = $null
    if (-not [string]::IsNullOrWhiteSpace($Username)) {
        $pair = "$($Username):$Token"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [Convert]::ToBase64String($bytes)
        $authHeader = @{ Authorization = "Basic $base64" }
    }
    else {
        $pair = "x-token-auth:$Token"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [Convert]::ToBase64String($bytes)
        $authHeader = @{ Authorization = "Basic $base64" }
    }

    try {
        $currentUser = Invoke-BitbucketApi -Uri "https://api.bitbucket.org/2.0/user" -Headers $authHeader
    }
    catch { return @() }
    $myUuid = $currentUser.uuid

    # Optimization: Only check repos updated in the last 90 days to avoid rate limits
    $minDate = (Get-Date).AddDays(-90).ToString("yyyy-MM-dd")
    $repoUrl = "https://api.bitbucket.org/2.0/repositories/${Workspace}?pagelen=100&sort=-updated_on&q=updated_on>=${minDate}"

    try {
        # Use Paged Result for Repositories
        $repos = Get-BitbucketPagedResult -Uri $repoUrl -Headers $authHeader
    }
    catch {
        Write-Error "Failed to fetch Bitbucket repositories: $_"
        return @()
    }

    if (-not $repos) { return @() }

    $bbResults = @()
    $apiState = "OPEN"
    if ($Mode -eq 'ApprovedAndMergedSince') { $apiState = "MERGED" }

    foreach ($repo in $repos) {
        $q = "state=`"$apiState`""
        if ($Mode -eq 'ApprovedAndMergedSince') {
            $q += " AND updated_on >= $DateStr"
        }

        $fields = "values.id,values.title,values.links.html.href,values.state,values.author.display_name,values.updated_on,values.merged_on,values.created_on,values.participants.user.uuid,values.participants.approved,values.reviewers.uuid,next"
        $prUrl = "https://api.bitbucket.org/2.0/repositories/$($repo.full_name)/pullrequests?q=$q&sort=-updated_on&pagelen=50&fields=$fields"

        try {
            # Use Paged Result for PRs
            $repoPrs = Get-BitbucketPagedResult -Uri $prUrl -Headers $authHeader

            if ($repoPrs) {
                foreach ($pr in $repoPrs) {
                    $include = $false
                    $meAsParticipant = $null
                    if ($pr.participants) {
                        $meAsParticipant = $pr.participants | Where-Object { $_.user.uuid -eq $myUuid } | Select-Object -First 1
                    }
                    $meAsReviewer = $null
                    if ($pr.reviewers) {
                        $meAsReviewer = $pr.reviewers | Where-Object { $_.uuid -eq $myUuid } | Select-Object -First 1
                    }

                    if ($Mode -eq 'Default') {
                        if ($meAsReviewer) { $include = $true }
                    }
                    elseif ($Mode -eq 'ApprovedAndOpen') {
                        if ($meAsParticipant.approved) { $include = $true }
                    }
                    elseif ($Mode -eq 'ApprovedAndMergedSince') {
                        if ($meAsParticipant.approved) { $include = $true }
                    }

                    if ($include) {
                        # Count all approvals from participants and check if I approved
                        $approvalCount = 0
                        $iApproved = $false
                        if ($pr.participants) {
                            $approvalCount = ($pr.participants | Where-Object { $_.approved -eq $true }).Count
                            if ($meAsParticipant -and $meAsParticipant.approved) { $iApproved = $true }
                        }
                        # Count reviewers
                        $reviewerCount = if ($pr.reviewers) { $pr.reviewers.Count } else { 0 }

                        $bbResults += [PSCustomObject]@{
                            Source        = "Bitbucket"
                            Repository    = $repo.name
                            ID            = $pr.id
                            Title         = $pr.title
                            Author        = $pr.author.display_name
                            URL           = $pr.links.html.href
                            State         = $pr.state
                            ApprovalCount = $approvalCount
                            AssigneeCount = $reviewerCount
                            IApproved     = $iApproved
                            Created       = if ($pr.created_on) { Get-Date $pr.created_on } else { $null }
                            Date          = if ($pr.merged_on) { $pr.merged_on } else { $pr.updated_on }
                        }
                    }
                }
            }
        }
        catch {
            Write-Error "Failed to fetch PRs for $($repo.full_name): $_"
        }
    }
    return $bbResults
}

# -----------------------------------------------------------------------------
# Display Function with Spectre.Console
# -----------------------------------------------------------------------------
function Show-PRTable {
    param([array]$Prs)

    if (-not $Prs -or $Prs.Count -eq 0) {
        Write-SpectreHost "[yellow]✅ All clear! No PRs found.[/]"
        return
    }

    Clear-Host
    
    # Create table data
    $tableData = @()
    foreach ($pr in $Prs) {
        $total = if ($pr.AssigneeCount -gt 0) { $pr.AssigneeCount } else { '?' }
        $myApproval = if ($pr.IApproved) { '✅' } else { '' }
        $appr = "$($pr.ApprovalCount)/$total$myApproval"
        
        # Abbreviate source
        $src = switch ($pr.Source) {
            'GitHub'    { 'GH' }
            'Bitbucket' { 'BB' }
            default     { $pr.Source }
        }
        
        # Truncate title to ~35 characters
        $title = $pr.Title
        if ($title.Length -gt 35) {
            $title = $title.Substring(0, 32) + '...'
        }
        
        # Escape any brackets in the title for Spectre markup
        $escapedTitle = $title -replace '\[', '[[' -replace '\]', ']]'
        
        # Create clickable link using Spectre markup
        $titleLink = "[link=$($pr.URL)]$escapedTitle[/]"
        
        # Truncate author if too long
        $author = $pr.Author
        if ($author.Length -gt 15) {
            $author = $author.Substring(0, 12) + '...'
        }
        
        $tableData += [PSCustomObject]@{
            '✓'    = $appr
            Src    = $src
            Repo   = $pr.Repository
            PR     = $pr.ID
            Title  = $titleLink
            Author = $author
            Date   = if ($pr.Created) { ([DateTime]$pr.Created).ToString('MM-dd') } else { 'N/A' }
        }
    }
    
    # Display table with -AllowMarkup to enable clickable links
    $tableData | Format-SpectreTable -Border Rounded -Title "Pull Requests" -AllowMarkup
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

$watchSpecified = $PSBoundParameters.ContainsKey('Watch')
$runLoop = -not $Once -and ($watchSpecified -or $PSCmdlet.ParameterSetName -eq 'Default')
$refreshMinutes = $Watch

# State tracking for notifications
$knownPrKeys = [System.Collections.Generic.HashSet[string]]::new()
$firstRun = $true

do {
    if ($runLoop -and -not $Once) { Clear-Host }

    # Start Jobs
    $dateArg = if ($ApprovedAndMergedSince) { $ApprovedAndMergedSince.ToString("yyyy-MM-dd") } else { (Get-Date).ToString("yyyy-MM-dd") }

    $jGH = Start-Job -ScriptBlock $sbGitHub -ArgumentList $GitHubOrg, $mode, $dateArg
    $jBB = $null
    if (-not $SkipBitbucket) {
        $jBB = Start-Job -ScriptBlock $sbBitbucket -ArgumentList $BitbucketWorkspace, $mode, $dateArg, $env:BITBUCKET_API_KEY, $env:BITBUCKET_USERNAME
    }

    # Wait for jobs to complete
    $null = Wait-Job $jGH
    if ($jBB) { $null = Wait-Job $jBB }

    # Collect Results
    $ghPrs = Receive-Job $jGH -ErrorAction SilentlyContinue
    $bbPrs = if ($jBB) { Receive-Job $jBB -ErrorAction SilentlyContinue } else { @() }
    $jobErrors = @()
    $jobErrors += $jGH.ChildJobs[0].Error
    if ($jBB) { $jobErrors += $jBB.ChildJobs[0].Error }
    Remove-Job $jGH
    if ($jBB) { Remove-Job $jBB }

    if ($jobErrors) {
        $rateLimitErrors = $jobErrors | Where-Object { $_ -match "Rate limit" -or $_ -match "429" }
        $otherErrors = $jobErrors | Where-Object { $_ -notmatch "Rate limit" -and $_ -notmatch "429" }

        if ($rateLimitErrors) {
            Write-Host "⚠️  Rate limit exceeded for $($rateLimitErrors.Count) repositories (even after retries)." -ForegroundColor Yellow
        }

        if ($otherErrors) {
            Write-Host "⚠️  Other errors occurred:" -ForegroundColor Yellow
            foreach ($err in $otherErrors) {
                Write-Host "  $err" -ForegroundColor Red
            }
        }
    }

    $allPrs = @()
    if ($ghPrs) { $allPrs += $ghPrs }
    if ($bbPrs) { $allPrs += $bbPrs }

    # -------------------------------------------------------------------------
    # Notification Logic
    # -------------------------------------------------------------------------
    $currentPrKeys = [System.Collections.Generic.HashSet[string]]::new()
    $newPrs = @()

    if ($allPrs) {
        foreach ($pr in $allPrs) {
            $key = "$($pr.Source)|$($pr.Repository)|$($pr.ID)"
            $null = $currentPrKeys.Add($key)

            if (-not $firstRun -and -not $knownPrKeys.Contains($key)) {
                $newPrs += $pr
            }
        }
    }

    if ($newPrs) {
        foreach ($nPr in $newPrs) {
            $msgTitle = "New PR: $($nPr.Repository)"
            $msgBody = $nPr.Title
            
            if (Get-Module -ListAvailable BurntToast) {
                try {
                    New-BurntToastNotification -Text $msgTitle, $msgBody -ErrorAction Stop
                } catch {
                    Write-Warning "Could not send toast: $_"
                }
            } else {
                Write-Host "`a" # Beep
            }
        }
    }

    # Only update state if we successfully fetched something or if there were no errors
    # This prevents clearing the cache on a complete network failure (0 PRs + Errors)
    if ($allPrs.Count -gt 0 -or -not $jobErrors) {
        $knownPrKeys = $currentPrKeys
        $firstRun = $false
    }

    if ($allPrs.Count -eq 0) {
        if ($jobErrors) {
            Write-Host "❌ No PRs found, but errors occurred (see above)." -ForegroundColor Red
        }
        else {
            Write-SpectreHost "[green]✅ All clear![/]"
        }
    }
    else {
        # Sort
        $sortedPrs = $allPrs | Sort-Object Source, Repository, ID

        # Display beautiful Spectre table
        Show-PRTable -Prs $sortedPrs
    }

    if ($runLoop) {
        $now = Get-Date
        $next = $now.AddMinutes($refreshMinutes)
        Write-Host ""
        Write-SpectreHost "[grey]Last run: $($now.ToString('HH:mm:ss'))  |  Next run: $($next.ToString('HH:mm:ss'))[/]"
        Start-Sleep -Seconds ($refreshMinutes * 60)
    }

} while ($runLoop)
