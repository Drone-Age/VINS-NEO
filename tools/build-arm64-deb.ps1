param(
    [string]$Version = "1.0.1.7",
    [string]$IrosVersion = "0.1.1",
    [string]$IrosDebVersion = "0.1.1-1+deb13",
    [string]$IrosSha256 = "62ef93734ae588cb5f342e902556d4cfa7b21de071bfedfe5b72c5431e42fe25",
    [string]$CvBridgeRef = "f5b738d9694f0cee5904440d03912fc249943f8a",
    [string]$OutputDirectory = "output",
    [switch]$SkipPreflight
)

$ErrorActionPreference = "Stop"

if (-not $SkipPreflight) {
    & "$PSScriptRoot/test-release.ps1" `
        -Version $Version `
        -IrosVersion $IrosVersion `
        -IrosDebVersion $IrosDebVersion `
        -IrosSha256 $IrosSha256 `
        -CvBridgeRef $CvBridgeRef `
        -BuildOnly
    if ($LASTEXITCODE -ne 0) {
        throw "Pre-release Docker build failed with exit code $LASTEXITCODE."
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

docker buildx build `
    --platform linux/arm64 `
    --file Dockerfile.rpi `
    --target deb `
    --build-arg "PACKAGE_VERSION=$Version" `
    --build-arg "IROS_VERSION=$IrosVersion" `
    --build-arg "IROS_DEB_VERSION=$IrosDebVersion" `
    --build-arg "IROS_SHA256=$IrosSha256" `
    --build-arg "CV_BRIDGE_REF=$CvBridgeRef" `
    --output "type=local,dest=$OutputDirectory" `
    .

if ($LASTEXITCODE -ne 0) {
    throw "ARM64 Debian package build failed with exit code $LASTEXITCODE."
}

$artifact = Get-Item -LiteralPath (
    Join-Path $OutputDirectory "vins-mono-ros2_${Version}_arm64.deb"
)
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName

[PSCustomObject]@{
    FullName = $artifact.FullName
    Length = $artifact.Length
    SHA256 = $hash.Hash
    LastWriteTime = $artifact.LastWriteTime
}
