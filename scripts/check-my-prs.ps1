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

    $searchQuery = "org:$Org"
    if ($Mode -eq 'ApprovedAndOpen') {
        $searchQuery += " review:approved reviewer:@me is:open"
    }
    elseif ($Mode -eq 'ApprovedAndMergedSince') {
        $searchQuery += " review:approved reviewer:@me is:merged merged:>=$DateStr"
    }
    else {
        $searchQuery += " review-requested:@me is:open"
    }

    $prs = gh pr list --search "$searchQuery" --json number,title,url,state,mergedAt,createdAt,author,reviews --limit 100 2>$null | ConvertFrom-Json

    if (-not $prs) { return @() }
    if ($prs -isnot [array]) { $prs = @($prs) }

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

    if ([string]::IsNullOrWhiteSpace($Token)) { return @() }

    function Invoke-BitbucketApi {
        param($Uri, $Headers)
        $attempt = 0
        $maxAttempts = 5
        while ($attempt -lt $maxAttempts) {
            $attempt++
            try {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -ErrorAction Stop
            } catch {
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

    # Auth Header
    $authHeader = $null
    if (-not [string]::IsNullOrWhiteSpace($Username)) {
        $pair = "$($Username):$Token"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [Convert]::ToBase64String($bytes)
        $authHeader = @{ Authorization = "Basic $base64" }
    } else {
        $pair = "x-token-auth:$Token"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [Convert]::ToBase64String($bytes)
        $authHeader = @{ Authorization = "Basic $base64" }
    }

    try {
        $currentUser = Invoke-BitbucketApi -Uri "https://api.bitbucket.org/2.0/user" -Headers $authHeader
    } catch { return @() }
    $myUuid = $currentUser.uuid

    # Optimization: Only check repos updated in the last 90 days to avoid rate limits
    $minDate = (Get-Date).AddDays(-90).ToString("yyyy-MM-dd")
    $repoUrl = "https://api.bitbucket.org/2.0/repositories/${Workspace}?pagelen=100&sort=-updated_on&q=updated_on>=${minDate}"

    try {
        $reposResp = Invoke-BitbucketApi -Uri $repoUrl -Headers $authHeader
        $repos = $reposResp.values
    } catch { return @() }

    if (-not $repos) { return @() }

    $bbResults = @()
    $apiState = "OPEN"
    if ($Mode -eq 'ApprovedAndMergedSince') { $apiState = "MERGED" }

    foreach ($repo in $repos) {
        $q = "state=`"$apiState`""
        if ($Mode -eq 'ApprovedAndMergedSince') {
            $q += " AND updated_on >= $DateStr"
        }

        $fields = "values.id,values.title,values.links.html.href,values.state,values.author.display_name,values.updated_on,values.merged_on,values.created_on,values.participants.user.uuid,values.participants.approved,values.reviewers.uuid"
        $prUrl = "https://api.bitbucket.org/2.0/repositories/$($repo.full_name)/pullrequests?q=$q&sort=-updated_on&pagelen=50&fields=$fields"

        try {
            $prResp = Invoke-BitbucketApi -Uri $prUrl -Headers $authHeader
            $repoPrs = $prResp.values

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
                        if ($meAsReviewer -and (-not $meAsParticipant.approved)) { $include = $true }
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
        } catch {
            Write-Error "Failed to fetch PRs for $($repo.full_name): $_"
        }
    }
    return $bbResults
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

$runLoop = $PSCmdlet.ParameterSetName -eq 'Default'

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

    if ($allPrs.Count -eq 0) {
        if ($jobErrors) {
            Write-Host "❌ No PRs found, but errors occurred (see above)." -ForegroundColor Red
        } else {
            Write-Host "✅ All clear!" -ForegroundColor Green
        }
    } else {
        # Sort
        $sortedPrs = $allPrs | Sort-Object Source, Repository, ID

        # Format Output
        $header = "{0,-8} {1,-10} {2,-12} {3,-25} {4,-50} {5}" -f 'Approved', 'Status', 'Created', 'Repo', 'Title', 'Link'
        Write-Host $header

        foreach ($pr in $sortedPrs) {
            $appr = if ($pr.Approved) { '✅' } else { '⭕' }
            $created = if ($pr.Created) { ([DateTime]$pr.Created).ToString('yyyy-MM-dd') } else { '' }

            $repo = $pr.Repository
            if ($repo.Length -gt 25) { $repo = $repo.Substring(0, 22) + '...' }

            $title = $pr.Title
            if ($title.Length -gt 50) { $title = $title.Substring(0, 47) + '...' }

            # Emoji alignment fix: "{0,-7}" pads 1 char to 7 chars (adds 6 spaces). Visual: 2+6=8.
            $line = "{0,-7} {1,-10} {2,-12} {3,-25} {4,-50} {5}" -f $appr, $pr.State, $created, $repo, $title, $pr.URL
            Write-Host $line
        }
    }

    if ($runLoop) {
        $now = Get-Date
        $next = $now.AddMinutes(15)
        Write-Host ""
        Write-Host "Last run: $($now.ToString('HH:mm:ss'))" -ForegroundColor DarkGray
        Write-Host "Next run: $($next.ToString('HH:mm:ss'))" -ForegroundColor DarkGray
        Start-Sleep -Seconds (15 * 60)
    }

} while ($runLoop)
