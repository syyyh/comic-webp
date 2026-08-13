$ErrorActionPreference = 'Stop'

flutter build apk --release --target-platform android-arm64 --split-per-abi
if ($LASTEXITCODE -ne 0) {
    throw "Flutter ARM64 build failed with exit code $LASTEXITCODE"
}

$apk = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
Write-Host "ARM64 APK: $apk"
