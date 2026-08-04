# Release manifests

Кожний новий реліз VINS-NEO має незмінний файл
`config/releases/<RELEASE_TAG>.env` у release-коміті.

Schema 3 фіксує VINS version/tag, точний підписаний APT snapshot `iros2j` і
замикання пакетів `iros2j-*`, сумісну ідентичність release/artifact iMAVROS,
системну версію OpenCV і точні назви Ubuntu 24.04/Jazzy AMD64 test/deployment
assets. Runtime prefixes: `/opt/iros2j`, `/opt/imavros` і `/opt/vins`. Поля
`CV_BRIDGE_REF` немає: `cv_bridge` надає `iros2j-cv-bridge`.

AMD64 fields завжди мають evidence class `development`. Вони роблять image,
Debian package, JSON manifest і список checksums обов’язковими versioned release
assets, але не послаблюють і не замінюють native Debian 13 ARM64 release gate.

Перевірка staged release:

```powershell
.\tools\check-release-metadata.ps1 `
  -Index -ReleaseTag v1_00_03_00 -VerifyAsset
```

Перевірка commit до створення tag:

```powershell
.\tools\check-release-metadata.ps1 `
  -GitRef HEAD -ReleaseTag v1_00_03_00
```

Файли schema 1 і 2 залишаються незмінними історичними контрактами.
