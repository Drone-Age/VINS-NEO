[CmdletBinding()]
param(
    [string]$GitRef = "HEAD",
    [string]$ReleaseTag,
    [switch]$Index,
    [switch]$VerifyAsset
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Parse-EnvLines {
    param([Parameter(Mandatory)][string[]]$Lines)
    $values = @{}
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -notmatch '^([A-Z][A-Z0-9_]*)=(.*)$') {
            throw "Invalid release manifest entry: $line"
        }
        $values[$matches[1]] = $matches[2].Trim()
    }
    return $values
}

function Require-ManifestValue {
    param([hashtable]$Manifest, [string]$Name)
    if (-not $Manifest.ContainsKey($Name) -or
        [string]::IsNullOrWhiteSpace($Manifest[$Name])) {
        throw "Release manifest is missing $Name."
    }
    return $Manifest[$Name]
}

function Git-Text {
    param([string]$Ref, [string]$Path, [switch]$FromIndex)
    $object = if ($FromIndex) { ":$Path" } else { "${Ref}:$Path" }
    $text = git show $object 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "$Path is absent from $object."
    }
    return ($text -join "`n")
}

Push-Location $repoRoot
try {
    $commit = if ($Index) {
        "INDEX"
    } else {
        git rev-parse --verify "$GitRef^{commit}"
    }
    if (-not $Index -and $LASTEXITCODE -ne 0) {
        throw "Unknown Git revision: $GitRef"
    }

    if (-not $ReleaseTag) {
        if ($Index) {
            throw "ReleaseTag is required with -Index."
        }
        $ReleaseTag = git describe --tags --exact-match $GitRef 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $ReleaseTag) {
            throw "ReleaseTag is required when GitRef is not an exact tag."
        }
    }
    if ($ReleaseTag -notmatch '^v\d+_\d{2}_\d{2}_\d{2}$') {
        throw "Invalid release tag: $ReleaseTag"
    }

    $manifestPath = "config/releases/$ReleaseTag.env"
    $manifestObject = if ($Index) {
        ":$manifestPath"
    } else {
        "${GitRef}:$manifestPath"
    }
    $savedErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $manifestLines = git show $manifestObject 2>$null
    $ErrorActionPreference = $savedErrorPreference
    $manifestIsCommitted = $LASTEXITCODE -eq 0
    if (-not $manifestIsCommitted) {
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            throw "$manifestPath is absent from both $GitRef and the worktree."
        }
        $manifestLines = Get-Content -Encoding UTF8 -LiteralPath $manifestPath
    }
    $manifest = Parse-EnvLines $manifestLines

    $required = @(
        "MANIFEST_SCHEMA", "PRODUCT_VERSION", "RELEASE_TAG",
        "IROS_VERSION", "IROS_DEB_VERSION", "IROS_RELEASE_URL",
        "IROS_ASSET_URL", "IROS_SHA256", "CV_BRIDGE_REF", "OPENCV_VERSION"
    )
    foreach ($name in $required) {
        $null = Require-ManifestValue $manifest $name
    }
    if ($manifest["MANIFEST_SCHEMA"] -ne "1") {
        throw "Unsupported MANIFEST_SCHEMA: $($manifest['MANIFEST_SCHEMA'])"
    }
    if ($manifest["RELEASE_TAG"] -ne $ReleaseTag) {
        throw "Manifest RELEASE_TAG does not match $ReleaseTag."
    }

    if (-not $manifestIsCommitted) {
        if ($manifest["MANIFEST_MODE"] -ne "backfill" -or
            $manifest["SOURCE_COMMIT"] -ne $commit.ToString().Trim()) {
            throw (
                "$manifestPath must be committed in the same release commit. " +
                "Only an explicit historical backfill tied to SOURCE_COMMIT is allowed."
            )
        }
    } elseif ($manifest.ContainsKey("MANIFEST_MODE") -and
        $manifest["MANIFEST_MODE"] -eq "backfill") {
        throw "New committed release manifests cannot use MANIFEST_MODE=backfill."
    }

    $version = $manifest["PRODUCT_VERSION"]
    if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') {
        throw "Invalid PRODUCT_VERSION: $version"
    }
    $derivedTag = "v{0}_{1:D2}_{2:D2}_{3:D2}" -f
        [int]$matches[1], [int]$matches[2], [int]$matches[3], [int]$matches[4]
    if ($derivedTag -ne $ReleaseTag) {
        throw "$version maps to $derivedTag, not $ReleaseTag."
    }

    $cmake = Git-Text $GitRef "vins_estimator/CMakeLists.txt" -FromIndex:$Index
    $header = Git-Text $GitRef "vins_estimator/src/version.h.in" -FromIndex:$Index
    $changelog = Git-Text $GitRef "CHANGELOG.md" -FromIndex:$Index
    if ($cmake -notmatch "project\(vins_estimator VERSION $([regex]::Escape($version))\)") {
        throw "CMake product version does not match the release manifest."
    }
    if ($header -notmatch [regex]::Escape($ReleaseTag)) {
        throw "version.h.in release tag does not match the release manifest."
    }
    if ($changelog -notmatch "(?m)^## \[$([regex]::Escape($ReleaseTag))\]") {
        throw "CHANGELOG.md has no release entry for $ReleaseTag."
    }

    $irosVersion = $manifest["IROS_VERSION"]
    $irosDebVersion = $manifest["IROS_DEB_VERSION"]
    $expectedReleaseUrl =
        "https://github.com/Drone-Age/iros2_0/releases/tag/v$irosVersion"
    $expectedAssetUrl =
        "https://github.com/Drone-Age/iros2_0/releases/download/" +
        "v$irosVersion/iros2-0_${irosDebVersion}_arm64.deb"
    if ($manifest["IROS_RELEASE_URL"] -ne $expectedReleaseUrl) {
        throw "IROS_RELEASE_URL is inconsistent with IROS_VERSION."
    }
    if ($manifest["IROS_ASSET_URL"] -ne $expectedAssetUrl) {
        throw "IROS_ASSET_URL is inconsistent with IROS_DEB_VERSION."
    }
    if ($manifest["IROS_SHA256"] -notmatch '^[0-9a-f]{64}$') {
        throw "IROS_SHA256 must be a lowercase SHA-256 digest."
    }
    if ($manifest["CV_BRIDGE_REF"] -notmatch '^[0-9a-f]{40}$') {
        throw "CV_BRIDGE_REF must be a full Git SHA."
    }

    if ($VerifyAsset) {
        $temporary = Join-Path ([System.IO.Path]::GetTempPath()) (
            "iros2-" + [guid]::NewGuid().ToString("N") + ".deb"
        )
        try {
            Invoke-WebRequest -UseBasicParsing `
                -Uri $manifest["IROS_ASSET_URL"] -OutFile $temporary
            $actualHash = (
                Get-FileHash -Algorithm SHA256 -LiteralPath $temporary
            ).Hash.ToLowerInvariant()
            if ($actualHash -ne $manifest["IROS_SHA256"]) {
                throw "Downloaded iROS2 SHA-256 does not match the manifest."
            }
        }
        finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -Force -LiteralPath $temporary
            }
        }
    }

    [PSCustomObject]@{
        GitRef = if ($Index) { "INDEX" } else { $GitRef }
        Commit = $commit.ToString().Trim()
        ReleaseTag = $ReleaseTag
        ProductVersion = $version
        IrosDebVersion = $irosDebVersion
        Manifest = $manifestPath
        ManifestCommittedInRelease = $manifestIsCommitted
        AssetVerified = [bool]$VerifyAsset
    }
}
finally {
    Pop-Location
}
