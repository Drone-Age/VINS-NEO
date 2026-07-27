# Release manifests

Кожний новий реліз VINS-NEO має незмінний файл
`config/releases/<RELEASE_TAG>.env` у release-коміті.

Schema 2 фіксує VINS version/tag, точний підписаний APT snapshot `iros2j` і
замикання пакетів `iros2j-*`, сумісну ідентичність release/artifact iMAVROS
та системну версію OpenCV. Runtime prefixes: `/opt/iros2j`, `/opt/imavros` і
`/opt/vins`. Поля `CV_BRIDGE_REF` немає: `cv_bridge` надає
`iros2j-cv-bridge`.

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

Файли schema 1 залишаються незмінними історичними контрактами.
