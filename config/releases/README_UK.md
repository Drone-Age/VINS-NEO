# Маніфести залежностей релізів

Кожний новий реліз VINS-NEO має власний файл:

```text
config/releases/<RELEASE_TAG>.env
```

Планування починається зі створення issue через форму
`.github/ISSUE_TEMPLATE/release.yml`. Значення iROS2 з issue переносяться до
маніфесту лише після повторної перевірки останнього стабільного релізу.

Маніфест входить до того самого Git-коміту, що й нова версія CMake, release tag
у `vins_estimator/src/version.h.in` та відповідний запис `CHANGELOG.md`.

Приклад для нового релізу:

```dotenv
MANIFEST_SCHEMA=1
PRODUCT_VERSION=1.0.1.8
RELEASE_TAG=v1_00_01_08
IROS_VERSION=0.1.2
IROS_DEB_VERSION=0.1.2-1+deb13
IROS_RELEASE_URL=https://github.com/Drone-Age/iros2_0/releases/tag/v0.1.2
IROS_ASSET_URL=https://github.com/Drone-Age/iros2_0/releases/download/v0.1.2/iros2-0_0.1.2-1+deb13_arm64.deb
IROS_SHA256=<64 lowercase hexadecimal characters>
CV_BRIDGE_REF=<full 40-character Git SHA>
OPENCV_VERSION=4.10.0
```

До створення release-коміту всі пов’язані файли потрібно додати до Git index
і перевірити:

```powershell
.\tools\check-release-metadata.ps1 `
  -Index -ReleaseTag v1_00_01_08 -VerifyAsset
```

Після коміту й до створення Git-тегу:

```powershell
.\tools\check-release-metadata.ps1 `
  -GitRef HEAD -ReleaseTag v1_00_01_08
```

`MANIFEST_MODE=backfill` дозволений лише для явно задокументованих історичних
тегів, створених до запровадження цього правила. Нові релізи з таким полем
metadata gate відхиляє.
