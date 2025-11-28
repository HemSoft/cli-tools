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
    [switch]$Help
)

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
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

    # Get current user
    $currentUser = gh api user --jq .login 2>$null

    # Build search queries - for default mode, search both authored and review-requested PRs
    $searchQueries = @()
    if ($Mode -eq 'ApprovedAndOpen') {
        $searchQueries += "org:$Org review:approved reviewer:@me is:open"
    }
    elseif ($Mode -eq 'ApprovedAndMergedSince') {
        $searchQueries += "org:$Org review:approved reviewer:@me is:merged merged:>=$DateStr"
    }
    else {
        # Default mode: show both PRs I authored AND PRs where I'm a reviewer
        $searchQueries += "org:$Org author:@me is:open"
        $searchQueries += "org:$Org reviewer:@me is:open"
    }

    $allPrs = @()
    $seenUrls = @{}

    foreach ($searchQuery in $searchQueries) {
        $ghOutput = gh pr list --search "$searchQuery" --json number,title,url,state,mergedAt,createdAt,author,reviews --limit 100 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "GitHub CLI error: $ghOutput"
            continue
        }

        try {
            $prs = $ghOutput | ConvertFrom-Json
        } catch {
            if ([string]::IsNullOrWhiteSpace($ghOutput)) { continue }
            Write-Error "Failed to parse GitHub JSON: $_"
            continue
        }

        if ($prs) {
            if ($prs -isnot [array]) { $prs = @($prs) }
            foreach ($pr in $prs) {
                if (-not $seenUrls.ContainsKey($pr.url)) {
                    $seenUrls[$pr.url] = $true
                    $allPrs += $pr
                }
            }
        }
    }

    $prs = $allPrs
    if (-not $prs) { return @() }

    return $prs | ForEach-Object {
        $repoName = ($_.url -split '/')[-3]

        $isApproved = $false
        if ($currentUser) {
            $lastReview = $_.reviews | Where-Object { $_.author.login -eq $currentUser } | Sort-Object submittedAt -Descending | Select-Object -First 1
            if ($lastReview.state -eq 'APPROVED') { $isApproved = $true }
        }
        if (-not $currentUser -and $Mode -like 'Approved*') { $isApproved = $true }

        [PSCustomObject]@{
            Source     = "GitHub"
            Repository = $repoName
            ID         = $_.number
            Title      = $_.title
            Author     = $_.author.login
            URL        = $_.url
            State      = $_.state
            Approved   = $isApproved
            Created    = if ($_.createdAt) { Get-Date $_.createdAt } else { $null }
            Date       = if ($_.mergedAt) { $_.mergedAt } else { $null }
        }
    }
}

# -----------------------------------------------------------------------------
# Bitbucket Job Logic
# -----------------------------------------------------------------------------
$sbBitbucket = {
    param($Workspace, $Mode, $DateStr, $Token, $Username)

    $env:BITBUCKET_API_TOKEN = $Token
    $env:BITBUCKET_USERNAME = $Username

    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Warning "Bitbucket Token is missing. Skipping Bitbucket checks."
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
                        $bbResults += [PSCustomObject]@{
                            Source     = "Bitbucket"
                            Repository = $repo.name
                            ID         = $pr.id
                            Title      = $pr.title
                            Author     = $pr.author.display_name
                            URL        = $pr.links.html.href
                            State      = $pr.state
                            Approved   = [bool]$meAsParticipant.approved
                            Created    = if ($pr.created_on) { Get-Date $pr.created_on } else { $null }
                            Date       = if ($pr.merged_on) { $pr.merged_on } else { $pr.updated_on }
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
# Main Execution
# -----------------------------------------------------------------------------

$runLoop = $PSCmdlet.ParameterSetName -eq 'Default'
if (-not $runLoop) { Clear-Host }

# State tracking for notifications
$knownPrKeys = [System.Collections.Generic.HashSet[string]]::new()
$firstRun = $true

do {
    if ($runLoop) { Clear-Host }

    # Start Jobs
    $dateArg = if ($ApprovedAndMergedSince) { $ApprovedAndMergedSince.ToString("yyyy-MM-dd") } else { (Get-Date).ToString("yyyy-MM-dd") }

    $jGH = Start-Job -ScriptBlock $sbGitHub -ArgumentList $GitHubOrg, $mode, $dateArg
    $jBB = Start-Job -ScriptBlock $sbBitbucket -ArgumentList $BitbucketWorkspace, $mode, $dateArg, $env:BITBUCKET_API_TOKEN, $env:BITBUCKET_USERNAME

    # Spinner
    $sp = @('|', '/', '-', '\')
    $idx = 0
    Write-Host -NoNewline " " # Initial space
    while ($jGH.State -eq 'Running' -or $jBB.State -eq 'Running') {
        Write-Host -NoNewline "`b$($sp[$idx])"
        Start-Sleep -Milliseconds 100
        $idx = ($idx + 1) % $sp.Length
    }
    Write-Host -NoNewline "`b " # Clear spinner
    Write-Host "" # Newline

    # Collect Results
    $ghPrs = Receive-Job $jGH -ErrorAction SilentlyContinue
    $bbPrs = Receive-Job $jBB -ErrorAction SilentlyContinue
    $jobErrors = @()
    $jobErrors += $jGH.ChildJobs[0].Error
    $jobErrors += $jBB.ChildJobs[0].Error
    Remove-Job $jGH, $jBB

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
            Write-Host "✅ All clear!" -ForegroundColor Green
        }
    }
    else {
        # Sort
        $sortedPrs = $allPrs | Sort-Object Source, Repository, ID

        # Calculate Dynamic Widths
        $termWidth = 120
        try { $termWidth = $Host.UI.RawUI.WindowSize.Width } catch {}
        if (-not $termWidth) { $termWidth = 120 }

        # Fixed columns: Approved(8) + Status(11) + Created(13) + Spacer(1) = 33 chars
        # Reserve 1 char buffer to prevent wrapping
        $available = $termWidth - 34
        if ($available -lt 30) { $available = 30 }

        # Distribute: Repo ~ 30%, Author ~ 70%
        $repoWidth = [Math]::Max(15, [int]($available * 0.30))
        $authorWidth = [Math]::Max(10, ($available - $repoWidth))

        # Format Output
        $headerFmt = "{0,-8} {1,-10} {2,-12} {3,-$repoWidth} {4,-$authorWidth}"
        $header = $headerFmt -f 'Approved', 'Status', 'Created', 'Repo', 'Author'
        Write-Host $header

        foreach ($pr in $sortedPrs) {
            $appr = if ($pr.Approved) { '✅' } else { '⭕' }
            $created = if ($pr.Created) { ([DateTime]$pr.Created).ToString('yyyy-MM-dd') } else { '' }

            $repo = $pr.Repository
            if ($repo.Length -gt $repoWidth) { $repo = $repo.Substring(0, $repoWidth - 3) + '...' }

            $author = $pr.Author
            if ($author.Length -gt $authorWidth) { $author = $author.Substring(0, $authorWidth - 3) + '...' }

            # Emoji alignment fix: "{0,-7}" pads 1 char to 7 chars (adds 6 spaces). Visual: 2+6=8.
            $lineFmt = "{0,-7} {1,-10} {2,-12} {3,-$repoWidth} {4,-$authorWidth}"
            $line = $lineFmt -f $appr, $pr.State, $created, $repo, $author
            Write-Host $line
            Write-Host "         $($pr.Title)" -ForegroundColor Cyan
            Write-Host "         $($pr.URL)" -ForegroundColor DarkGray
        }
    }

    if ($runLoop) {
        $now = Get-Date
        $next = $now.AddMinutes(15)
        Write-Host ""
        Write-Host "Last run: $($now.ToString('HH:mm:ss'))  |  Next run: $($next.ToString('HH:mm:ss'))" -ForegroundColor DarkGray
        Start-Sleep -Seconds (15 * 60)
    }

} while ($runLoop)
