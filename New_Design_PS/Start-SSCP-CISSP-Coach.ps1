$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

if (-not (Test-Path -LiteralPath (Join-Path $root "node_modules"))) {
    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    npm install
}

$launchUrl = "http://localhost:3000/sscp"

Start-Process -FilePath "powershell" -WorkingDirectory $root -ArgumentList @(
    "-NoExit",
    "-Command",
    "npm run dev"
)

Start-Sleep -Seconds 8
Start-Process $launchUrl

Write-Host ""
Write-Host "SSCP + CISSP Coach is launching." -ForegroundColor Green
Write-Host "Tutor URL: $launchUrl"
Write-Host "Extension folder: $root\\browser-extension\\sscp-companion"
