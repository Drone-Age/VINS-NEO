# Процес випуску

Це чинний release-контракт для VINS-NEO 1.0.3.0 і новіших версій. Історичні
релізи залишаються під керуванням незмінних файлів у відповідних тегах.

## Вхідні дані

До release-коміту schema 3 `config/releases/<RELEASE_TAG>.env` ОБОВ’ЯЗКОВО
фіксує:

- версію й тег продукту VINS;
- версію та Debian-версію `iros2j`, source tag і commit, URL та SHA-256
  підписаного APT snapshot, `/opt/iros2j` і точне замикання `iros2j-*`;
- сумісні версію та Debian-версію iMAVROS, tag, commit, URL та SHA-256
  артефакту і `/opt/imavros`;
- системну версію OpenCV.
- Ubuntu 24.04/Jazzy AMD64 test-платформу, evidence class `development` і точні
  назви versioned image, Debian package, JSON manifest та checksum assets.

Перед dataset gate підготовлений на host DataSetsManager run-manifest
ОБОВ’ЯЗКОВО фіксує dataset ID і profile, artifact version та source/content
SHA-256, configuration SHA-256, suite version і DataSetsManager Client version.
Dispatcher передає перевірені inputs на Pi без DSM token.

Schema 2 та 3 НЕ МАЮТЬ містити `CV_BRIDGE_REF`. VINS використовує
`iros2j-cv-bridge` і не клонує та не збирає `vision_opencv`.

## Gate-перевірки

1. Додати до index manifest, CMake-версію, runtime tag, changelog, scripts,
   tests і парну документацію.
2. Виконати `tools/check-release-metadata.ps1 -Index -ReleaseTag <TAG>
   -VerifyAsset` і переглянути повну release-зміну.
3. Злити release-зміну без створення tag або GitHub Release. Зафіксувати точний
   фінальний commit у release issue і заморозити його для обох архітектурних
   gate.
4. На цьому точному фінальному commit виконати
   `tools/check-release-metadata.ps1 -GitRef HEAD -ReleaseTag <TAG>` та
   `tools/build-amd64-test-release.ps1 -ReleaseTag <TAG>`.
5. На Ubuntu 24.04 AMD64 виконати реальний dataset e2e `iv.dev.4.ff.1`. Result
   ОБОВ’ЯЗКОВО має бути `PASS` з evidence class `development` і тим самим
   точним фінальним commit. Зберегти AMD64 test/deployment assets і hashes.
6. Підготувати `iv.dev.4.ff.1` через HTTPS DSM endpoint на host і вказати
   `DATASET_RUN_MANIFEST` в ignored native environment.
7. Із того самого точного commit виконати native Debian 13 ARM64 workflow:
   `tools/invoke-native-release.ps1 -InstallDependencies -InstallTest
   -IntegrationTest -DatasetTest`.
8. Перевірити ARM64 Debian package, clean installation, ELF closure, точні
   залежності `iros2j-*` і власність файлів у `/opt/vins`.
9. Перевірити, що ARM64 `dataset-e2e-result.json` має `PASS`, evidence class
   `release` і той самий точний фінальний commit.
10. Створити незмінні product/process tags на цьому commit. GitHub Release
    ОБОВ’ЯЗКОВО містить AMD64 test/deployment image, AMD64 Debian package,
    AMD64 JSON manifest, checksums і dataset evidence, а також ARM64
    production package, checksums і release evidence.
11. Завантажити кожний опублікований artifact, перевірити checksum,
    перевстановити або завантажити його на відповідній платформі та повторити
    застосовні smoke й integration checks.

Tag або release не створюється, доки обов’язковий gate має стан `FAIL`,
`BLOCKED` або `NOT_RUN`. Якщо виправлення змінює заморожений commit, обидва
gate — AMD64 і ARM64 — ОБОВ’ЯЗКОВО запускаються знову з нового фінального
commit; evidence зі старого commit не переноситься.
