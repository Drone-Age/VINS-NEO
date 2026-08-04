[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+_\d{2}_\d{2}_\d{2}$')]
    [string]$ReleaseTag,

    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Parse-ReleaseManifest {
    param([Parameter(Mandatory)][string]$Path)

    $values = @{}
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -notmatch '^([A-Z][A-Z0-9_]*)=(.*)$') {
            throw "Invalid release manifest entry: $line"
        }
        $values[$matches[1]] = $matches[2].Trim()
    }
    return $values
}

function Get-RequiredValue {
    param([hashtable]$Values, [string]$Name)

    if (-not $Values.ContainsKey($Name) -or
        [string]::IsNullOrWhiteSpace($Values[$Name])) {
        throw "Release manifest is missing $Name."
    }
    return $Values[$Name]
}

function Get-AssetRecord {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    return [ordered]@{
        name = $File.Name
        sha256 = (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $File.FullName).Hash.ToLowerInvariant()
        size_bytes = $File.Length
    }
}

Push-Location $repoRoot
try {
    $status = @(git status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot inspect the Git worktree."
    }
    if ($status.Count -ne 0) {
        throw (
            "The AMD64 release build requires a clean exact commit. " +
            "Commit or remove worktree changes first."
        )
    }

    $sourceCommit = (git rev-parse --verify 'HEAD^{commit}').Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') {
        throw "Cannot resolve the exact source commit."
    }

    $manifestPath = Join-Path $repoRoot "config/releases/$ReleaseTag.env"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Release manifest does not exist: $manifestPath"
    }
    $release = Parse-ReleaseManifest $manifestPath
    $productVersion = Get-RequiredValue $release "PRODUCT_VERSION"

    & "$PSScriptRoot/check-release-metadata.ps1" `
        -GitRef HEAD -ReleaseTag $ReleaseTag
    if ($LASTEXITCODE -ne 0) {
        throw "Release metadata validation failed."
    }

    $imageAssetName = Get-RequiredValue $release "AMD64_TEST_IMAGE_ASSET"
    $debAssetName = Get-RequiredValue $release "AMD64_TEST_DEB_ASSET"
    $resultAssetName = Get-RequiredValue $release "AMD64_TEST_MANIFEST_ASSET"
    $checksumAssetName = Get-RequiredValue $release "AMD64_TEST_CHECKSUM_ASSET"

    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path $repoRoot "output/amd64-release"
    }
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $OutputDirectory) {
        $existing = @(Get-ChildItem -Force -LiteralPath $OutputDirectory)
        if ($existing.Count -ne 0) {
            throw "Output directory must be empty: $OutputDirectory"
        }
    } else {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    Invoke-Checked docker @("version", "--format", "{{.Server.Os}}")
    $imageTag = "vins-neo-test-env:$productVersion-ubuntu24-amd64"
    $commonBuildArguments = @(
        "buildx", "build",
        "--platform", "linux/amd64",
        "--build-arg", "ROS_DISTRO=jazzy",
        "--build-arg", "PRODUCT_VERSION=$productVersion",
        "--build-arg", "RELEASE_TAG=$ReleaseTag",
        "--build-arg", "SOURCE_COMMIT=$sourceCommit"
    )

    Invoke-Checked docker ($commonBuildArguments + @(
        "--target", "test-runtime",
        "--tag", $imageTag,
        "--load", "."
    ))

    $imageInspection = @(& docker image inspect $imageTag) -join "`n" |
        ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $imageInspection) {
        throw "Cannot inspect the built image."
    }
    $imagePlatform =
        "$($imageInspection[0].Os)/$($imageInspection[0].Architecture)"
    if ($imagePlatform -ne "linux/amd64") {
        throw "Built image platform is $imagePlatform, expected linux/amd64."
    }
    $imageRevision =
        $imageInspection[0].Config.Labels.'org.opencontainers.image.revision'
    if ($imageRevision -ne $sourceCommit) {
        throw "Built image revision label does not match the source commit."
    }
    $imageId = $imageInspection[0].Id
    if (-not $imageId) {
        throw "Cannot resolve the built image ID."
    }

    Invoke-Checked docker @(
        "run", "--rm", "--platform", "linux/amd64", $imageTag, "version"
    )

    $imageAsset = Join-Path $OutputDirectory $imageAssetName
    Invoke-Checked docker @("image", "save", "--output", $imageAsset, $imageTag)

    $temporaryDebOutput = Join-Path $OutputDirectory (
        ".deb-stage-" + [guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path $temporaryDebOutput | Out-Null
    try {
        Invoke-Checked docker ($commonBuildArguments + @(
            "--build-arg", "PACKAGE_VERSION=$productVersion",
            "--target", "deb",
            "--output", "type=local,dest=$temporaryDebOutput", "."
        ))
        $builtDebs = @(Get-ChildItem -File -Recurse -Filter "*.deb" `
            -LiteralPath $temporaryDebOutput)
        if ($builtDebs.Count -ne 1) {
            throw "Expected exactly one AMD64 Debian package."
        }
        $debAsset = Join-Path $OutputDirectory $debAssetName
        Move-Item -LiteralPath $builtDebs[0].FullName -Destination $debAsset
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDebOutput) {
            Remove-Item -Recurse -Force -LiteralPath $temporaryDebOutput
        }
    }

    $debDirectory = Split-Path -Parent $debAsset
    $debName = Split-Path -Leaf $debAsset
    $debIdentity = @{}
    foreach ($field in @("Package", "Version", "Architecture")) {
        $value = (& docker run --rm --platform linux/amd64 `
            --entrypoint dpkg-deb `
            --volume "${debDirectory}:/assets:ro" `
            $imageTag -f "/assets/$debName" $field).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $value) {
            throw "Cannot inspect Debian package field $field."
        }
        $debIdentity[$field] = $value
    }
    if ($debIdentity["Package"] -ne "vins-mono-ros2" -or
        $debIdentity["Version"] -ne $productVersion -or
        $debIdentity["Architecture"] -ne "amd64") {
        throw "AMD64 Debian package identity does not match the release."
    }

    $imageRecord = Get-AssetRecord (Get-Item -LiteralPath $imageAsset)
    $debRecord = Get-AssetRecord (Get-Item -LiteralPath $debAsset)
    $createdAt = [DateTimeOffset]::UtcNow.ToString("o")
    $result = [ordered]@{
        schema_version = "1.0"
        result = "PASS"
        evidence_class = "development"
        purpose = @("local-first-test", "test-environment-deployment")
        release = [ordered]@{
            product_version = $productVersion
            tag = $ReleaseTag
            source_commit = $sourceCommit
        }
        platform = [ordered]@{
            os = "ubuntu-24.04"
            architecture = "amd64"
            docker_platform = "linux/amd64"
            ros_distro = "jazzy"
        }
        tests = [ordered]@{
            colcon = "PASS"
            repository_contracts = "PASS"
            debian_package_install_smoke = "PASS"
            executed_by = @("Dockerfile:test", "Dockerfile:deb-smoke")
        }
        image = [ordered]@{
            tag = $imageTag
            id = $imageId
            asset = $imageRecord
        }
        debian_package = [ordered]@{
            package = "vins-mono-ros2"
            version = $productVersion
            architecture = "amd64"
            asset = $debRecord
        }
        created_at = $createdAt
    }

    $resultAsset = Join-Path $OutputDirectory $resultAssetName
    $json = $result | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $resultAsset,
        $json + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    $resultRecord = Get-AssetRecord (Get-Item -LiteralPath $resultAsset)

    $checksumAsset = Join-Path $OutputDirectory $checksumAssetName
    $checksumLines = @(
        "$($imageRecord.sha256)  $($imageRecord.name)",
        "$($debRecord.sha256)  $($debRecord.name)",
        "$($resultRecord.sha256)  $($resultRecord.name)"
    )
    [System.IO.File]::WriteAllLines(
        $checksumAsset,
        $checksumLines,
        [System.Text.UTF8Encoding]::new($false)
    )

    [PSCustomObject]@{
        Result = "PASS"
        EvidenceClass = "development"
        ReleaseTag = $ReleaseTag
        SourceCommit = $sourceCommit
        Platform = $imagePlatform
        OutputDirectory = $OutputDirectory
        ImageAsset = $imageRecord.name
        DebianAsset = $debRecord.name
        ManifestAsset = $resultRecord.name
        ChecksumAsset = $checksumAssetName
    }
}
finally {
    Pop-Location
}
