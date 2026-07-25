[CmdletBinding()]
param(
    [string]$GitRef,
    [string]$ReleaseTag,
    [string]$NativeConfig = "config/native/native.env",
    [switch]$PreflightOnly,
    [switch]$InstallDependencies,
    [switch]$InstallTest,
    [switch]$DatasetTest,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

function Read-EnvFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file does not exist: $Path"
    }

    $result = @{}
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        if ($trimmed -notmatch '^([A-Z][A-Z0-9_]*)=(.*)$') {
            throw "Invalid environment entry in ${Path}: $line"
        }
        $result[$matches[1]] = $matches[2].Trim()
    }
    return $result
}

function Require-Value {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Values.ContainsKey($Name) -or
        [string]::IsNullOrWhiteSpace($Values[$Name])) {
        throw "Required setting is missing: $Name"
    }
    return $Values[$Name]
}

function Assert-SafeValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Pattern
    )

    if ($Value -notmatch $Pattern) {
        throw "Unsafe or invalid value for ${Name}: $Value"
    }
}

foreach ($command in "git", "ssh", "scp", "tar") {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $command"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $hostConfig = Read-EnvFile $NativeConfig
    $nativeHost = Require-Value $hostConfig "NATIVE_HOST"
    $nativeUser = Require-Value $hostConfig "NATIVE_USER"
    $nativePort = if ($hostConfig.ContainsKey("NATIVE_SSH_PORT")) {
        $hostConfig["NATIVE_SSH_PORT"]
    } else {
        "22"
    }
    $outputDirectory = Require-Value $hostConfig "OUTPUT_DIR"
    $null = Require-Value $hostConfig "NATIVE_UNAME_ARCH"
    $null = Require-Value $hostConfig "NATIVE_DEB_ARCH"

    Assert-SafeValue "NATIVE_HOST" $nativeHost '^[A-Za-z0-9._:-]+$'
    Assert-SafeValue "NATIVE_USER" $nativeUser '^[A-Za-z_][A-Za-z0-9_-]*$'
    Assert-SafeValue "NATIVE_SSH_PORT" $nativePort '^\d{1,5}$'
    Assert-SafeValue "OUTPUT_DIR" $outputDirectory '^/[A-Za-z0-9._/-]+$'

    if (-not $GitRef) {
        $GitRef = (
            git tag --merged HEAD --sort=-version:refname |
                Select-Object -First 1
        )
        if (-not $GitRef) {
            throw "No version tag reachable from HEAD was found."
        }
    }

    git rev-parse --verify "$GitRef^{commit}" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Git revision does not exist: $GitRef"
    }

    if (-not $ReleaseTag) {
        $ReleaseTag = git describe --tags --exact-match $GitRef 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $ReleaseTag) {
            throw (
                "ReleaseTag is required when building an untagged release commit: " +
                "$GitRef"
            )
        }
    }
    Assert-SafeValue "release tag" $ReleaseTag '^v\d+_\d{2}_\d{2}_\d{2}$'

    & "$PSScriptRoot/check-release-metadata.ps1" `
        -GitRef $GitRef -ReleaseTag $ReleaseTag | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Release metadata gate failed."
    }

    $manifestPath = "config/releases/$ReleaseTag.env"
    $manifest = Read-EnvFile $manifestPath
    foreach ($required in @(
        "PRODUCT_VERSION",
        "RELEASE_TAG",
        "IROS_VERSION",
        "IROS_DEB_VERSION",
        "IROS_RELEASE_URL",
        "IROS_ASSET_URL",
        "IROS_SHA256",
        "CV_BRIDGE_REF",
        "OPENCV_VERSION"
    )) {
        $null = Require-Value $manifest $required
    }
    if ($manifest["RELEASE_TAG"] -ne $ReleaseTag) {
        throw "Release manifest tag does not match $ReleaseTag."
    }

    $target = "${nativeUser}@${nativeHost}"
    $sshOptions = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-p", $nativePort
    )

    Write-Host "Native target: $target"
    Write-Host "Release: $ReleaseTag ($($manifest['PRODUCT_VERSION']))"
    Write-Host "Running remote preflight..."

    $preflight = @(
        "set -eu",
        "test `"`$(uname -m)`" = `"$($hostConfig['NATIVE_UNAME_ARCH'])`"",
        "test `"`$(dpkg --print-architecture)`" = `"$($hostConfig['NATIVE_DEB_ARCH'])`"",
        "grep -Eq '^VERSION_ID=.*13' /etc/os-release",
        "mkdir -p '$outputDirectory'"
    )
    if (-not $InstallDependencies) {
        $preflight += @(
            "test -f /opt/iros2_0/jazzy/setup.bash",
            "test `"`$(dpkg-query -W iros2-0 | cut -f2)`" = `"$($manifest['IROS_DEB_VERSION'])`""
        )
    }
    $preflight = $preflight -join "; "
    Write-Verbose "Remote preflight: $preflight"
    & ssh @sshOptions $target $preflight
    if ($LASTEXITCODE -ne 0) {
        throw "Native ARM64 preflight failed."
    }

    if ($PreflightOnly) {
        Write-Host "Native ARM64 preflight passed."
        return
    }

    $commit = git rev-parse "$GitRef^{commit}"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $remoteRunDirectory = "$outputDirectory/$ReleaseTag/$stamp-$($commit.Substring(0, 12))"
    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
        "vins-native-" + [guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    try {
        $sourceArchive = Join-Path $temporaryDirectory "source.tar"
        $nativeScript = Join-Path $repoRoot "tools/native-release.sh"

        git archive --format=tar --output=$sourceArchive $GitRef
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to archive Git revision $GitRef."
        }

        & ssh @sshOptions $target (
            "mkdir -p '$remoteRunDirectory/source' '$remoteRunDirectory/evidence'"
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create the isolated remote release directory."
        }

        & scp -P $nativePort -q -- $sourceArchive (
            "${target}:$remoteRunDirectory/source.tar"
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to transfer the source archive."
        }
        & scp -P $nativePort -q -- $nativeScript (
            "${target}:$remoteRunDirectory/native-release.sh"
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to transfer the native release script."
        }

        $remotePrepare = @(
            "set -eu",
            "tar -xf '$remoteRunDirectory/source.tar' -C '$remoteRunDirectory/source'",
            "chmod 0755 '$remoteRunDirectory/native-release.sh'",
            "rm -f '$remoteRunDirectory/source.tar'"
        ) -join "; "
        & ssh @sshOptions $target $remotePrepare
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to prepare the remote release workspace."
        }

        $arguments = @(
            "--source", "'$remoteRunDirectory/source'",
            "--evidence", "'$remoteRunDirectory/evidence'",
            "--version", "'$($manifest['PRODUCT_VERSION'])'",
            "--tag", "'$ReleaseTag'",
            "--commit", "'$commit'",
            "--iros-version", "'$($manifest['IROS_VERSION'])'",
            "--iros-deb-version", "'$($manifest['IROS_DEB_VERSION'])'",
            "--iros-asset-url", "'$($manifest['IROS_ASSET_URL'])'",
            "--iros-sha256", "'$($manifest['IROS_SHA256'])'",
            "--cv-bridge-ref", "'$($manifest['CV_BRIDGE_REF'])'",
            "--opencv-version", "'$($manifest['OPENCV_VERSION'])'"
        )
        if ($InstallDependencies) { $arguments += "--install-dependencies" }
        if ($InstallTest) { $arguments += "--install-test" }
        if ($SkipTests) { $arguments += "--skip-tests" }
        if ($DatasetTest) {
            $arguments += @(
                "--dataset-test",
                "--vins-config", "'$($hostConfig['VINS_CONFIG'])'",
                "--dataset", "'$($hostConfig['DATASET'])'",
                "--dataset-runner", "'$($hostConfig['DATASET_TEST_RUNNER'])'"
            )
        }

        $remoteCommand = (
            "'$remoteRunDirectory/native-release.sh' " + ($arguments -join " ")
        )
        & ssh @sshOptions $target $remoteCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Native release workflow failed. Evidence: $remoteRunDirectory/evidence"
        }

        Write-Host "Native release workflow passed."
        Write-Host "Remote evidence: $remoteRunDirectory/evidence"
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -Recurse -Force -LiteralPath $temporaryDirectory
        }
    }
}
finally {
    Pop-Location
}
