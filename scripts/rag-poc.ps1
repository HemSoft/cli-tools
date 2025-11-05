#!/usr/bin/env pwsh
#Requires -Version 7.3

<#
.SYNOPSIS
    Launch RAG POC application
.DESCRIPTION
    Runs the RAG POC application from its build output
#>

$ErrorActionPreference = "Stop"

# Navigate to RAG POC directory and run
Push-Location "F:\github\HemSoft\rag-poc"
try {
    & ".\run.ps1"
}
finally {
    Pop-Location
}
