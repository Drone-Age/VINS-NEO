# Процес випуску

Це чинний release-контракт для VINS-NEO 1.0.3.0 і новіших версій. Історичні
релізи залишаються під керуванням незмінних файлів у відповідних тегах.

## Вхідні дані

До release-коміту `config/releases/<RELEASE_TAG>.env` ОБОВ’ЯЗКОВО фіксує:

- версію й тег продукту VINS;
- версію та Debian-версію `iros2j`, source tag і commit, URL та SHA-256
  підписаного APT snapshot, `/opt/iros2j` і точне замикання `iros2j-*`;
- сумісні версію та Debian-версію iMAVROS, tag, commit, URL та SHA-256
  артефакту і `/opt/imavros`;
- системну версію OpenCV.

Schema 2 НЕ МАЄ містити `CV_BRIDGE_REF`. VINS використовує
`iros2j-cv-bridge` і не клонує та не збирає `vision_opencv`.

## Gate-перевірки

1. Додати до index manifest, CMake-версію, runtime tag, changelog, scripts,
   tests і парну документацію.
2. Виконати `tools/check-release-metadata.ps1 -Index -ReleaseTag <TAG>
   -VerifyAsset`.
3. Переглянути й закомітити повну release-зміну.
4. Виконати `tools/check-release-metadata.ps1 -GitRef HEAD -ReleaseTag <TAG>`.
5. Виконати native Debian 13 ARM64 workflow командою
   `tools/invoke-native-release.ps1 -InstallDependencies -InstallTest
   -IntegrationTest -DatasetTest`.
6. Перевірити Debian package, clean installation, ELF closure, точні
   залежності `iros2j-*` і власність файлів у `/opt/vins`.
7. Злити перевірений commit, після чого створити незмінні product/process
   tags і release assets.
8. Завантажити опублікований artifact, перевірити checksum, перевстановити
   його й повторити smoke та integration checks.

Tag або release не створюється, доки обов’язковий gate має стан `FAIL`,
`BLOCKED` або `NOT_RUN`.
