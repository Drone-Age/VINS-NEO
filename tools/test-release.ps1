param(
    [string]$Version = "1.0.1.7",
    [string]$IrosVersion = "0.1.1",
    [string]$IrosDebVersion = "0.1.1-1+deb13",
    [string]$IrosSha256 = "62ef93734ae588cb5f342e902556d4cfa7b21de071bfedfe5b72c5431e42fe25",
    [string]$CvBridgeRef = "f5b738d9694f0cee5904440d03912fc249943f8a",
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
$expectedTag = "v1_00_01_07"

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $Name"
    }
}

function Assert-Text {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Description
    )

    if (-not (Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)) {
        throw "$Description is inconsistent in $Path."
    }
}

Assert-Command git
Assert-Command docker

if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Product version must use MAJOR.MINOR.FEATURE.PATCH."
}

$parts = $Version.Split(".")
$derivedTag = "v{0}_{1:D2}_{2:D2}_{3:D2}" -f
    [int]$parts[0], [int]$parts[1], [int]$parts[2], [int]$parts[3]

if ($derivedTag -ne $expectedTag) {
    throw "Version $Version maps to $derivedTag, but the release expects $expectedTag."
}

Assert-Text "vins_estimator/CMakeLists.txt" `
    "project\(vins_estimator VERSION $([regex]::Escape($Version))\)" `
    "Product version"
Assert-Text "vins_estimator/src/version.h.in" `
    ([regex]::Escape($expectedTag)) `
    "Release tag"
Assert-Text "CHANGELOG.md" `
    ([regex]::Escape("## [$expectedTag]")) `
    "CHANGELOG release"

$dockerInfo = docker version --format "{{.Server.Os}}/{{.Server.Arch}}"
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop is not available."
}

$platforms = docker buildx inspect --bootstrap |
    Select-String -Pattern "Platforms:"
if (-not ($platforms -match "linux/arm64")) {
    throw "Docker Buildx does not support linux/arm64."
}

Write-Host "Docker server: $dockerInfo"
Write-Host "Building and testing Debian 13 ARM64 release gate..."

docker buildx build `
    --platform linux/arm64 `
    --file Dockerfile.rpi `
    --target pre-release `
    --build-arg "PACKAGE_VERSION=$Version" `
    --build-arg "IROS_VERSION=$IrosVersion" `
    --build-arg "IROS_DEB_VERSION=$IrosDebVersion" `
    --build-arg "IROS_SHA256=$IrosSha256" `
    --build-arg "CV_BRIDGE_REF=$CvBridgeRef" `
    --progress plain `
    .

if ($LASTEXITCODE -ne 0) {
    throw "Pre-release gate failed with exit code $LASTEXITCODE."
}

if (-not $BuildOnly) {
    Write-Host "Pre-release gate passed for $Version ($expectedTag)."
}
