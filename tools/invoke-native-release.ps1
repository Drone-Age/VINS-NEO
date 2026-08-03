[CmdletBinding()]
param(
    [string]$GitRef,
    [string]$ReleaseTag,
    [string]$NativeConfig = "config/native/native.env",
    [switch]$PreflightOnly,
    [switch]$InstallDependencies,
    [switch]$InstallTest,
    [switch]$IntegrationTest,
    [switch]$DatasetTest,
    [string]$DatasetRunManifest,
    [switch]$SkipTests,
    [switch]$WorkingTree
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
    $nativeIdentityFile = if ($hostConfig.ContainsKey("NATIVE_IDENTITY_FILE")) {
        $hostConfig["NATIVE_IDENTITY_FILE"]
    } else {
        ""
    }
    $outputDirectory = Require-Value $hostConfig "OUTPUT_DIR"
    $null = Require-Value $hostConfig "NATIVE_UNAME_ARCH"
    $null = Require-Value $hostConfig "NATIVE_DEB_ARCH"

    Assert-SafeValue "NATIVE_HOST" $nativeHost '^[A-Za-z0-9._:-]+$'
    Assert-SafeValue "NATIVE_USER" $nativeUser '^[A-Za-z_][A-Za-z0-9_-]*$'
    Assert-SafeValue "NATIVE_SSH_PORT" $nativePort '^\d{1,5}$'
    Assert-SafeValue "OUTPUT_DIR" $outputDirectory '^/[A-Za-z0-9._/-]+$'
    if ($nativeHost -ne "192.168.144.106" -or $nativeUser -ne "rpi") {
        throw "Native target must be exactly rpi@192.168.144.106."
    }

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

    $metadataArguments = @{
        GitRef = $GitRef
        ReleaseTag = $ReleaseTag
    }
    if ($WorkingTree) {
        $metadataArguments["Index"] = $true
        Write-Warning (
            "Working-tree diagnostic mode is not final release evidence. " +
            "Repeat against the committed release tag before publication."
        )
    }
    & "$PSScriptRoot/check-release-metadata.ps1" @metadataArguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Release metadata gate failed."
    }

    $manifestPath = "config/releases/$ReleaseTag.env"
    $manifest = Read-EnvFile $manifestPath
    foreach ($required in @(
        "MANIFEST_SCHEMA",
        "PRODUCT_VERSION",
        "RELEASE_TAG",
        "IROS_VERSION",
        "IROS_DEB_VERSION",
        "IROS_SOURCE_TAG",
        "IROS_SOURCE_COMMIT",
        "IROS_RELEASE_URL",
        "IROS_ASSET_URL",
        "IROS_SHA256",
        "IROS_PREFIX",
        "IROS_PACKAGES",
        "IROS_RUNTIME_PACKAGES",
        "IMAVROS_VERSION",
        "IMAVROS_DEB_VERSION",
        "IMAVROS_TAG",
        "IMAVROS_COMMIT",
        "IMAVROS_PREFIX",
        "OPENCV_VERSION"
    )) {
        $null = Require-Value $manifest $required
    }
    if ($manifest["RELEASE_TAG"] -ne $ReleaseTag) {
        throw "Release manifest tag does not match $ReleaseTag."
    }
    if ($manifest["MANIFEST_SCHEMA"] -ne "2") {
        throw "Native iros2j release requires MANIFEST_SCHEMA=2."
    }

    $target = "${nativeUser}@${nativeHost}"
    $sshOptions = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-p", $nativePort
    )
    $scpOptions = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-P", $nativePort
    )
    if (-not [string]::IsNullOrWhiteSpace($nativeIdentityFile)) {
        if (-not (Test-Path -LiteralPath $nativeIdentityFile -PathType Leaf)) {
            throw "NATIVE_IDENTITY_FILE does not exist: $nativeIdentityFile"
        }
        $nativeIdentityFile = (Resolve-Path -LiteralPath $nativeIdentityFile).Path
        $sshOptions += @("-o", "IdentitiesOnly=yes", "-i", $nativeIdentityFile)
        $scpOptions += @("-o", "IdentitiesOnly=yes", "-i", $nativeIdentityFile)
    }

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
        $packageChecks = $manifest["IROS_PACKAGES"].Split(",") |
            ForEach-Object {
                "test `"`$(dpkg-query -W -f='`${Version}' '$_')`" = " +
                "`"$($manifest['IROS_DEB_VERSION'])`""
            }
        $preflight += @(
            "test ! -e /opt/iros2_0",
            "! dpkg-query -W iros2-0 >/dev/null 2>&1",
            "test -f /opt/iros2j/setup.bash"
        )
        $preflight += $packageChecks
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

        if ($WorkingTree) {
            $archiveFiles = @(git ls-files --cached --others --exclude-standard)
            if ($LASTEXITCODE -ne 0 -or $archiveFiles.Count -eq 0) {
                throw "Failed to enumerate working-tree source files."
            }
            & tar -cf $sourceArchive -- @archiveFiles
        } else {
            git archive --format=tar --output=$sourceArchive $GitRef
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to archive the requested source state."
        }

        & ssh @sshOptions $target (
            "mkdir -p '$remoteRunDirectory/source' '$remoteRunDirectory/evidence'"
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create the isolated remote release directory."
        }

        & scp @scpOptions -q -- $sourceArchive (
            "${target}:$remoteRunDirectory/source.tar"
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to transfer the source archive."
        }
        & scp @scpOptions -q -- $nativeScript (
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
            "--iros-source-tag", "'$($manifest['IROS_SOURCE_TAG'])'",
            "--iros-source-commit", "'$($manifest['IROS_SOURCE_COMMIT'])'",
            "--iros-asset-url", "'$($manifest['IROS_ASSET_URL'])'",
            "--iros-sha256", "'$($manifest['IROS_SHA256'])'",
            "--iros-packages", "'$($manifest['IROS_PACKAGES'])'",
            "--iros-runtime-packages",
                "'$($manifest['IROS_RUNTIME_PACKAGES'])'",
            "--imavros-version", "'$($manifest['IMAVROS_VERSION'])'",
            "--imavros-deb-version", "'$($manifest['IMAVROS_DEB_VERSION'])'",
            "--imavros-tag", "'$($manifest['IMAVROS_TAG'])'",
            "--imavros-commit", "'$($manifest['IMAVROS_COMMIT'])'",
            "--imavros-prefix", "'$($manifest['IMAVROS_PREFIX'])'",
            "--opencv-version", "'$($manifest['OPENCV_VERSION'])'"
        )
        if ($InstallDependencies) { $arguments += "--install-dependencies" }
        if ($InstallTest) { $arguments += "--install-test" }
        if ($IntegrationTest) { $arguments += "--integration-test" }
        if ($SkipTests) { $arguments += "--skip-tests" }
        if ($DatasetTest) {
            $arguments += @(
                "--dataset-test",
                "--dataset-runner", "'$remoteRunDirectory/source/tools/dataset_e2e.py'"
            )
            $configuredRunManifest = if ($DatasetRunManifest) {
                $DatasetRunManifest
            } elseif ($hostConfig.ContainsKey("DATASET_RUN_MANIFEST")) {
                $hostConfig["DATASET_RUN_MANIFEST"]
            } else {
                ""
            }
            if (-not [string]::IsNullOrWhiteSpace($configuredRunManifest)) {
                $runManifestPath = (Resolve-Path -LiteralPath $configuredRunManifest).Path
                $runManifest = Get-Content -LiteralPath $runManifestPath -Raw -Encoding UTF8 |
                    ConvertFrom-Json
                foreach ($section in "artifact", "config") {
                    if ($null -eq $runManifest.$section -or
                        [string]::IsNullOrWhiteSpace($runManifest.$section.path)) {
                        throw "Prepared run manifest lacks $section.path."
                    }
                }
                $artifactSource = (Resolve-Path -LiteralPath $runManifest.artifact.path).Path
                $configSource = (Resolve-Path -LiteralPath $runManifest.config.path).Path
                if (-not (Test-Path -LiteralPath $configSource -PathType Leaf)) {
                    throw "Prepared VINS config is not a file: $configSource"
                }
                $portableRoot = Join-Path $temporaryDirectory "dataset-input"
                New-Item -ItemType Directory -Path $portableRoot | Out-Null
                Copy-Item -LiteralPath $artifactSource `
                    -Destination (Join-Path $portableRoot "artifact") -Recurse
                Copy-Item -LiteralPath $configSource `
                    -Destination (Join-Path $portableRoot "config.yaml")
                $runManifest.artifact.path = "artifact"
                $runManifest.config.path = "config.yaml"
                $portableManifest = Join-Path $portableRoot "run-manifest.json"
                $manifestJson = $runManifest | ConvertTo-Json -Depth 32
                [System.IO.File]::WriteAllText(
                    $portableManifest,
                    $manifestJson + "`n",
                    [System.Text.UTF8Encoding]::new($false)
                )
                $datasetArchive = Join-Path $temporaryDirectory "dataset-input.tar"
                & tar -cf $datasetArchive -C $portableRoot .
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to create the tokenless dataset input archive."
                }
                & ssh @sshOptions $target "mkdir -p '$remoteRunDirectory/dataset-input'"
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to create remote dataset input directory."
                }
                & scp @scpOptions -q -- $datasetArchive (
                    "${target}:$remoteRunDirectory/dataset-input.tar"
                )
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to transfer the tokenless dataset input archive."
                }
                & ssh @sshOptions $target (
                    "tar -xf '$remoteRunDirectory/dataset-input.tar' " +
                    "-C '$remoteRunDirectory/dataset-input' && " +
                    "rm -f '$remoteRunDirectory/dataset-input.tar'"
                )
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to unpack the remote dataset input archive."
                }
                $arguments += @(
                    "--dataset-run-manifest",
                    "'$remoteRunDirectory/dataset-input/run-manifest.json'"
                )
            } else {
                Write-Warning (
                    "VINS_CONFIG/DATASET are deprecated expert overrides. " +
                    "Prepare DATASET_RUN_MANIFEST on the host through HTTPS."
                )
                $arguments += @(
                    "--vins-config", "'$(Require-Value $hostConfig 'VINS_CONFIG')'",
                    "--dataset", "'$(Require-Value $hostConfig 'DATASET')'"
                )
            }
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
