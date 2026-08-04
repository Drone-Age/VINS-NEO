# Ubuntu 24.04 AMD64 test release

Кожний продуктовий реліз VINS-NEO ОБОВ’ЯЗКОВО містить Ubuntu 24.04/Jazzy AMD64
збірку для першого кола локальних тестів і розгортання відтворюваних тестових
середовищ. Ця збірка має версію продукту, але не є production target і не може
замінити native Debian 13 ARM64 release evidence.

## Контракт збірки

Запускайте з clean checkout точного фінального release commit:

```powershell
pwsh ./tools/build-amd64-test-release.ps1 `
  -ReleaseTag v1_00_03_00 `
  -OutputDirectory ./output/amd64-release
```

Команда ОБОВ’ЯЗКОВО завершується помилкою для dirty worktree, metadata
mismatch, не-AMD64 image, невдалого `colcon test`, невдалого repository
contract, неправильної image revision label, неправильної ідентичності Debian
package, невдалого clean package-install smoke або помилки запису asset.

Той самий builder доступний через ручний GitHub Actions workflow
**Ubuntu 24 AMD64 test release**. Запускайте його на замороженому фінальному
commit, а не на рухомій branch. Збережений workflow artifact є проміжним
handoff; після проходження ARM64 gate файли все одно ОБОВ’ЯЗКОВО додаються до
versioned GitHub Release.

Output contract фіксується schema 3 у
`config/releases/<RELEASE_TAG>.env` і містить:

- Docker image archive зі встановленим VINS overlay, RViz dependencies і
  VINS-owned dataset runner;
- Ubuntu 24.04/Jazzy AMD64 Debian package;
- JSON build manifest із `PASS`, `development`, product/tag, точним source
  commit, platform, image ID, ідентичністю package, sizes і hashes;
- один файл `SHA256SUMS` для трьох попередніх assets.

Image створюється лише зі stage Docker `test`, тому невдалі unit або contract
tests блокують створення image і package. Image підтримує entrypoints `shell`,
`version` та tokenless `dataset-e2e --run-manifest ...`. Artifact/config paths
із підготовленого manifest ОБОВ’ЯЗКОВО монтуються за тими самими абсолютними
шляхами всередині container.

Debian asset встановлюється в окремому VINS-free Ubuntu/Jazzy dependency stage
і ОБОВ’ЯЗКОВО запускає `vins_estimator --version`, перш ніж фінальний package
можна експортувати.

## Приймання релізу

На тому самому точному commit виконайте реальний smoke suite `iv.dev.4.ff.1`
на Ubuntu 24.04 AMD64 і збережіть `dataset-e2e-result.json` як evidence класу
`development`. Потім повторіть dataset і native package/integration gates на
Debian 13 ARM64; лише цей result є evidence класу `release`.

Після проходження обох gate додайте всі AMD64 assets і AMD64
`dataset-e2e-result.json` разом з ARM64 production assets/evidence до versioned
GitHub Release. Якщо виправлення змінює source commit, відкиньте evidence обох
архітектур і повторіть build/test з нового точного фінального commit.
