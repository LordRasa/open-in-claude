<#
    Packages OpenInClaude.ps1 into a single double-clickable OpenInClaude.exe
    with no console window. Uses the ps2exe module (installed per-user if missing).

    Run:  powershell -ExecutionPolicy Bypass -File build.ps1
#>

$ErrorActionPreference = 'Stop'
$here   = $PSScriptRoot
$src    = Join-Path $here 'OpenInClaude.ps1'
$out    = Join-Path $here 'OpenInClaude.exe'
$icon   = Join-Path $here 'icon.ico'

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Installing ps2exe (current user)...' -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

$params = @{
    inputFile  = $src
    outputFile = $out
    noConsole  = $true
    title      = 'Open in Claude'
    description= 'Open a folder as a new Claude Desktop Code session'
    company    = 'aR'
}
if (Test-Path -LiteralPath $icon) { $params.iconFile = $icon }

Write-Host "Building $out ..." -ForegroundColor Cyan
Invoke-ps2exe @params
Write-Host "Done. Double-click OpenInClaude.exe (no console flash)." -ForegroundColor Green
