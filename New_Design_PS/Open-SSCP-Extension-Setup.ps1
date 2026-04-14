$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$extensionPath = Join-Path $root "browser-extension\sscp-companion"
$tutorUrl = "http://localhost:3000/sscp"

function Get-BrowserPath {
    $candidates = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

$browserPath = Get-BrowserPath

if (-not (Test-Path -LiteralPath $extensionPath)) {
    throw "Extension folder not found: $extensionPath"
}

if ($browserPath) {
    $extensionsUrl = if ($browserPath -like "*msedge.exe") { "edge://extensions" } else { "chrome://extensions" }

    Start-Process -FilePath $browserPath -ArgumentList $tutorUrl
    Start-Process -FilePath $browserPath -ArgumentList $extensionsUrl
} else {
    Write-Warning "No supported browser executable was found automatically. Opening the tutor in the default browser instead."
    Start-Process $tutorUrl
}

Start-Process explorer.exe -ArgumentList $extensionPath

Write-Host ""
Write-Host "Browser extension setup is ready." -ForegroundColor Green
Write-Host "Tutor URL: $tutorUrl"
Write-Host "Extension folder: $extensionPath"
Write-Host ""
Write-Host "Next:"
Write-Host "1. Turn on Developer mode in the browser extensions page."
Write-Host "2. Click Load unpacked."
Write-Host "3. Choose the opened sscp-companion folder."
