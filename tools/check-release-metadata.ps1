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

function Get-ReleaseAsset {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )

    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
        return
    }
    catch {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -Force -LiteralPath $Destination
        }
        if ($Uri -notmatch (
            '^https://github\.com/([^/]+/[^/]+)/releases/download/' +
            '([^/]+)/([^/]+)$'
        )) {
            throw
        }
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw (
                "Release asset is not anonymously accessible and gh is " +
                "unavailable for authenticated private-release download: $Uri"
            )
        }
        $repository = $matches[1]
        $tag = $matches[2]
        $asset = [Uri]::UnescapeDataString($matches[3])
        & gh release download $tag --repo $repository `
            --pattern $asset --output $Destination
        if ($LASTEXITCODE -ne 0 -or
            -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            throw "Authenticated release asset download failed: $Uri"
        }
    }
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
        "IROS_ASSET_URL", "IROS_SHA256", "OPENCV_VERSION"
    )
    foreach ($name in $required) {
        $null = Require-ManifestValue $manifest $name
    }
    if ($manifest["MANIFEST_SCHEMA"] -notin @("1", "2")) {
        throw "Unsupported MANIFEST_SCHEMA: $($manifest['MANIFEST_SCHEMA'])"
    }
    if ($manifest["MANIFEST_SCHEMA"] -eq "2") {
        foreach ($name in @(
            "IROS_NAME", "IROS_SOURCE_TAG", "IROS_SOURCE_COMMIT",
            "IROS_PREFIX", "IROS_PACKAGES", "IROS_RUNTIME_PACKAGES",
            "IMAVROS_VERSION",
            "IMAVROS_DEB_VERSION", "IMAVROS_TAG", "IMAVROS_COMMIT",
            "IMAVROS_RELEASE_URL", "IMAVROS_ASSET_URL", "IMAVROS_SHA256",
            "IMAVROS_PREFIX"
        )) {
            $null = Require-ManifestValue $manifest $name
        }
    } else {
        $null = Require-ManifestValue $manifest "CV_BRIDGE_REF"
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
    $rosPackageVersion = "{0}.{1}.{2}" -f
        [int]$matches[1], [int]$matches[2], [int]$matches[3]
    foreach ($packagePath in @(
        "ar_demo/package.xml",
        "benchmark_publisher/package.xml",
        "camera_model/package.xml",
        "config_pkg/package.xml",
        "feature_tracker/package.xml",
        "pose_graph/package.xml",
        "vins_estimator/package.xml"
    )) {
        $packageXml = Git-Text $GitRef $packagePath -FromIndex:$Index
        if ($packageXml -notmatch
            "<version>$([regex]::Escape($rosPackageVersion))</version>") {
            throw (
                "$packagePath version does not match product version " +
                "$version."
            )
        }
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
    if ($manifest["MANIFEST_SCHEMA"] -eq "2") {
        if ($manifest["IROS_NAME"] -ne "iros2j") {
            throw "Schema 2 requires IROS_NAME=iros2j."
        }
        if ($manifest["IROS_PREFIX"] -ne "/opt/iros2j") {
            throw "Schema 2 requires IROS_PREFIX=/opt/iros2j."
        }
        if ($manifest["IMAVROS_PREFIX"] -ne "/opt/imavros") {
            throw "Schema 2 requires IMAVROS_PREFIX=/opt/imavros."
        }
        $expectedReleaseUrl =
            "https://github.com/Drone-Age/iros2_0/releases/tag/" +
            $manifest["IROS_SOURCE_TAG"]
        $expectedAssetUrl =
            "https://github.com/Drone-Age/iros2_0/releases/download/" +
            "$($manifest['IROS_SOURCE_TAG'])/iros2j-apt_trixie_arm64.tar.gz"
        if ($manifest["IROS_SOURCE_COMMIT"] -notmatch '^[0-9a-f]{40}$') {
            throw "IROS_SOURCE_COMMIT must be a full Git SHA."
        }
        if ($manifest["IROS_SOURCE_TAG"] -ne "v2.$irosVersion") {
            throw "IROS_SOURCE_TAG is inconsistent with IROS_VERSION."
        }
        if ($manifest["IMAVROS_COMMIT"] -notmatch '^[0-9a-f]{40}$') {
            throw "IMAVROS_COMMIT must be a full Git SHA."
        }
        if ($manifest["IMAVROS_TAG"] -ne "v$($manifest['IMAVROS_VERSION'])") {
            throw "IMAVROS_TAG is inconsistent with IMAVROS_VERSION."
        }
        if ($manifest["IMAVROS_DEB_VERSION"] -ne
            "$($manifest['IMAVROS_VERSION'])-1+deb13") {
            throw "IMAVROS_DEB_VERSION is inconsistent with IMAVROS_VERSION."
        }
        $expectedImavrosReleaseUrl =
            "https://github.com/Drone-Age/iMAVROS-release/releases/tag/" +
            $manifest["IMAVROS_TAG"]
        $expectedImavrosAssetUrl =
            "https://github.com/Drone-Age/iMAVROS-release/releases/download/" +
            "$($manifest['IMAVROS_TAG'])/imavros_latest_arm64.deb"
        if ($manifest["IMAVROS_RELEASE_URL"] -ne $expectedImavrosReleaseUrl) {
            throw "IMAVROS_RELEASE_URL is inconsistent with IMAVROS_TAG."
        }
        if ($manifest["IMAVROS_ASSET_URL"] -ne $expectedImavrosAssetUrl) {
            throw "IMAVROS_ASSET_URL is inconsistent with IMAVROS_DEB_VERSION."
        }
        if ($manifest["IMAVROS_SHA256"] -notmatch '^[0-9a-f]{64}$') {
            throw "IMAVROS_SHA256 must be a lowercase SHA-256 digest."
        }
        $irosPackages = $manifest["IROS_PACKAGES"].Split(",")
        foreach ($package in $irosPackages) {
            if ($package -notmatch '^iros2j-[a-z0-9][a-z0-9+.-]+$') {
                throw "Invalid iros2j package in IROS_PACKAGES: $package"
            }
        }
        if ($irosPackages -notcontains "iros2j-cv-bridge") {
            throw "IROS_PACKAGES must include iros2j-cv-bridge."
        }
        if (($irosPackages | Sort-Object -Unique).Count -ne
            $irosPackages.Count) {
            throw "IROS_PACKAGES contains duplicates."
        }
        $runtimePackages = $manifest["IROS_RUNTIME_PACKAGES"].Split(",")
        foreach ($package in $runtimePackages) {
            if ($irosPackages -notcontains $package) {
                throw (
                    "IROS_RUNTIME_PACKAGES is not a subset of IROS_PACKAGES: " +
                    $package
                )
            }
        }
    } else {
        $expectedReleaseUrl =
            "https://github.com/Drone-Age/iros2_0/releases/tag/v$irosVersion"
        $expectedAssetUrl =
            "https://github.com/Drone-Age/iros2_0/releases/download/" +
            "v$irosVersion/iros2-0_${irosDebVersion}_arm64.deb"
    }
    if ($manifest["IROS_RELEASE_URL"] -ne $expectedReleaseUrl) {
        throw "IROS_RELEASE_URL is inconsistent with IROS_VERSION."
    }
    if ($manifest["IROS_ASSET_URL"] -ne $expectedAssetUrl) {
        throw "IROS_ASSET_URL is inconsistent with IROS_DEB_VERSION."
    }
    if ($manifest["IROS_SHA256"] -notmatch '^[0-9a-f]{64}$') {
        throw "IROS_SHA256 must be a lowercase SHA-256 digest."
    }
    if ($manifest["MANIFEST_SCHEMA"] -eq "1" -and
        $manifest["CV_BRIDGE_REF"] -notmatch '^[0-9a-f]{40}$') {
        throw "CV_BRIDGE_REF must be a full Git SHA."
    }

    if ($VerifyAsset) {
        $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
            "vins-release-assets-" + [guid]::NewGuid().ToString("N")
        )
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
        try {
            $temporary = Join-Path $temporaryDirectory "iros2.asset"
            Get-ReleaseAsset -Uri $manifest["IROS_ASSET_URL"] `
                -Destination $temporary
            $actualHash = (
                Get-FileHash -Algorithm SHA256 -LiteralPath $temporary
            ).Hash.ToLowerInvariant()
            if ($actualHash -ne $manifest["IROS_SHA256"]) {
                throw "Downloaded iROS2 SHA-256 does not match the manifest."
            }
            if ($manifest["MANIFEST_SCHEMA"] -eq "2") {
                $imavrosTemporary = Join-Path $temporaryDirectory "imavros.deb"
                Get-ReleaseAsset -Uri $manifest["IMAVROS_ASSET_URL"] `
                    -Destination $imavrosTemporary
                $actualImavrosHash = (
                    Get-FileHash -Algorithm SHA256 `
                        -LiteralPath $imavrosTemporary
                ).Hash.ToLowerInvariant()
                if ($actualImavrosHash -ne $manifest["IMAVROS_SHA256"]) {
                    throw (
                        "Downloaded iMAVROS SHA-256 does not match the manifest."
                    )
                }
            }
        }
        finally {
            if (Test-Path -LiteralPath $temporaryDirectory) {
                Remove-Item -Recurse -Force -LiteralPath $temporaryDirectory
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
