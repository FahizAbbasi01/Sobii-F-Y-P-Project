# DeviceTrust — one-time Android setup (Windows PowerShell).
# Run from the mobile\ folder:   powershell -ExecutionPolicy Bypass -File .\setup_android.ps1
#
# 1. Generates the android\ folder with YOUR installed Flutter version (Android only, no iOS).
# 2. Allows plain HTTP to your local backend in DEBUG builds only (release stays HTTPS-only).
# 3. Sets minSdk 23 (needed by ML Kit text recognition and secure storage).
# 4. Fetches packages.
# Safe to re-run.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error "Flutter is not on PATH. Install it first (see README.md > 'Install Flutter on Windows')."
}

if (-not (Test-Path 'android')) {
  Write-Host 'Generating Android project...' -ForegroundColor Cyan
  # flutter create never overwrites existing files such as lib\ or pubspec.yaml.
  flutter create --platforms=android --org com.devicetrust --project-name devicetrust .
} else {
  Write-Host 'android\ already exists, applying settings only.' -ForegroundColor Yellow
}

# Write files as UTF-8 WITHOUT a BOM (Windows PowerShell's Set-Content adds one, which Gradle can choke on).
function Write-NoBom($path, $text) { [System.IO.File]::WriteAllText((Resolve-Path $path), $text, (New-Object System.Text.UTF8Encoding $false)) }

# Remove the counter-app test that flutter create adds (it doesn't match this app).
if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' }

# --- Debug-only cleartext HTTP (for http://10.0.2.2:4000 / LAN IP during development) ---
$debugManifest = 'android\app\src\debug\AndroidManifest.xml'
New-Item -ItemType Directory -Force (Split-Path $debugManifest) | Out-Null
if (-not (Test-Path $debugManifest)) { New-Item -ItemType File $debugManifest | Out-Null }
Write-NoBom $debugManifest @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Debug builds only: allow HTTP to the local DeviceTrust backend. Release builds require HTTPS. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true"/>
</manifest>
'@

# --- Release needs INTERNET too ---
$mainManifest = 'android\app\src\main\AndroidManifest.xml'
$m = Get-Content $mainManifest -Raw
if ($m -notmatch 'android.permission.INTERNET') {
  $m = $m -replace '(<manifest[^>]*>)', "`$1`r`n    <uses-permission android:name=`"android.permission.INTERNET`"/>"
}
$m = $m -replace 'android:label="[^"]*"', 'android:label="DeviceTrust"'
Write-NoBom $mainManifest $m

# --- minSdk 23 (works for both Kotlin DSL and Groovy Gradle files) ---
foreach ($g in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
  if (Test-Path $g) {
    $c = Get-Content $g -Raw
    $c = $c -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
    $c = $c -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
    $c = $c -replace 'minSdk\s+flutter\.minSdkVersion', 'minSdk 23'
    Write-NoBom $g $c
    Write-Host "Updated $g (minSdk 23)"
  }
}

Write-Host 'Fetching packages...' -ForegroundColor Cyan
flutter pub get
Write-Host ''
Write-Host 'Done. Next:' -ForegroundColor Green
Write-Host '  flutter analyze'
Write-Host '  flutter test'
Write-Host '  flutter run            (Android emulator: backend at http://10.0.2.2:4000)'
Write-Host '  flutter run --dart-define=API_BASE_URL=http://YOUR-PC-IP:4000   (real phone on same Wi-Fi)'
