# Native release environment

Офіційне release evidence створюється лише на налаштованій Raspberry Pi 5 з
Debian 13 ARM64. Скопіюйте `native.env.example` до ігнорованого `native.env`
і вкажіть затверджений host та output directory. Підготуйте DSM run-manifest
на host через HTTPS і задайте `DATASET_RUN_MANIFEST`. Dispatcher пакує
перевірені artifact, VINS configuration та manifest із відносними шляхами для
Pi; `DSM_SERVER_TOKEN` не передається.

Dispatcher перевіряє точну ідентичність target, передає archive вибраної Git
revision до ізольованого каталогу й запускає tracked native script:

```powershell
.\tools\invoke-native-release.ps1 -PreflightOnly
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

Runtime активується в порядку `/opt/iros2j`, `/opt/imavros`, `/opt/vins`.
`VINS_CONFIG` і `DATASET` є deprecated expert overrides на один цикл
сумісності. `native.env`, DSM keys і SSH credentials НЕ МОЖНА комітити.
