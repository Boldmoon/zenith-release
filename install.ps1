$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  +---------------------------------------+" -ForegroundColor Cyan
Write-Host "  |         ZENITH INSTALLER             |" -ForegroundColor Cyan
Write-Host "  |   Hardware Development Assistant     |" -ForegroundColor Cyan
Write-Host "  +---------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  System: Windows x64" -ForegroundColor White
Write-Host ""

$GitHubRepo = "Boldmoon/zenith-release"
$TempDir = [System.IO.Path]::GetTempPath()
$ExePath = Join-Path $TempDir "Zenith-Setup.exe"

Write-Host "  [1/4] Fetching latest release..." -ForegroundColor White

$MaxRetries = 3
$RetryDelay = 2
$Release = $null

for ($i = 1; $i -le $MaxRetries; $i++) {
    try {
        $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" -UseBasicParsing -TimeoutSec 30
        break
    } catch {
        if ($i -eq $MaxRetries) {
            Write-Host ""
            Write-Host "  ERROR: Failed to fetch release information after $MaxRetries attempts" -ForegroundColor Red
            Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  Please check your internet connection and try again." -ForegroundColor Yellow
            Write-Host "  Or visit: https://github.com/$GitHubRepo/releases" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
        Write-Host "        Attempt $i failed, retrying in $RetryDelay seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $RetryDelay
        $RetryDelay = $RetryDelay * 2
    }
}

$Version = $Release.tag_name
Write-Host "        Found version: $Version" -ForegroundColor Green
Write-Host ""

$Asset = $Release.assets | Where-Object { $_.name -like "*x64.exe" -or $_.name -like "*win*.exe" } | Select-Object -First 1

if (-not $Asset) {
    Write-Host ""
    Write-Host "  ERROR: Failed to find Windows installer" -ForegroundColor Red
    Write-Host "  Available assets:" -ForegroundColor DarkGray
    foreach ($a in $Release.assets) {
        Write-Host "    - $($a.name)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Please visit: https://github.com/$GitHubRepo/releases" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$SizeMB = [math]::Round($Asset.size / 1MB, 1)
Write-Host "  [2/4] Downloading Zenith ($SizeMB MB)..." -ForegroundColor White
Write-Host "        This may take a few minutes..." -ForegroundColor DarkGray

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $ExePath -UseBasicParsing -TimeoutSec 600
    $ProgressPreference = 'Continue'
} catch {
    Write-Host ""
    Write-Host "  ERROR: Download failed" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

Write-Host "        Download complete." -ForegroundColor Green
Write-Host ""

Write-Host "  [3/4] Preparing installer..." -ForegroundColor White

$ZoneIdentifierPath = "${ExePath}:Zone.Identifier"
if (Test-Path -LiteralPath $ZoneIdentifierPath -ErrorAction SilentlyContinue) {
    try {
        Remove-Item -LiteralPath $ZoneIdentifierPath -Force -ErrorAction SilentlyContinue
    } catch {}
}

try {
    Unblock-File -Path $ExePath -ErrorAction SilentlyContinue
} catch {}

Write-Host ""

Write-Host "  [4/4] Launching installer..." -ForegroundColor White
Write-Host ""

try {
    Start-Process -FilePath $ExePath
} catch {
    Write-Host ""
    Write-Host "  ERROR: Failed to run installer" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

Write-Host "  +---------------------------------------+" -ForegroundColor Green
Write-Host "  |      Installer launched!             |" -ForegroundColor Green
Write-Host "  +---------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Follow the installer prompts to complete installation." -ForegroundColor White
Write-Host "  You can close this window." -ForegroundColor DarkGray
Write-Host ""
