param(
    [string]$Version = $(if ($env:SCHELM_VERSION) { $env:SCHELM_VERSION } else { "0.1.0-alpha.1" }),
    [string]$InstallDir = $(if ($env:SCHELM_INSTALL_DIR) { $env:SCHELM_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\Schelm\bin" })
)

$ErrorActionPreference = "Stop"
if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Schelm currently supports 64-bit Windows only."
}

$asset = "schelm-$Version-windows-x86_64.zip"
$base = "https://github.com/sjalq/schelm-elm-compiler/releases/download/v$Version"
$work = Join-Path ([IO.Path]::GetTempPath()) ("schelm-install-" + [Guid]::NewGuid())

try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $archive = Join-Path $work $asset
    $checksum = "$archive.sha256"
    Invoke-WebRequest -UseBasicParsing -Uri "$base/$asset" -OutFile $archive
    Invoke-WebRequest -UseBasicParsing -Uri "$base/$asset.sha256" -OutFile $checksum

    $expected = ((Get-Content -LiteralPath $checksum -Raw).Trim() -split '\s+')[0]
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') { throw "Invalid checksum file." }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
    if ($actual -ne $expected) { throw "Checksum verification failed." }

    Expand-Archive -LiteralPath $archive -DestinationPath $work
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item -Force -Path (Join-Path $work "schelm\bin\*") -Destination $InstallDir

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable("Path", ((@($entries) + $InstallDir) -join ';'), "User")
        Write-Host "Added $InstallDir to your user PATH. Open a new terminal to use it."
    }
    if (($env:Path -split ';') -notcontains $InstallDir) { $env:Path += ";$InstallDir" }

    Write-Host "Installed Schelm $Version at $InstallDir\schelm.exe"
    & (Join-Path $InstallDir "schelm.exe") --version-full
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $work
}
