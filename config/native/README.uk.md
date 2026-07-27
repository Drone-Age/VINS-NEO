# Native release environment

Офіційне release evidence створюється лише на налаштованій Raspberry Pi 5 з
Debian 13 ARM64. Скопіюйте `native.env.example` до ігнорованого `native.env`
і вкажіть затверджений host, output directory, VINS configuration, dataset і
dataset runner.

Dispatcher перевіряє точну ідентичність target, передає archive вибраної Git
revision до ізольованого каталогу й запускає tracked native script:

```powershell
.\tools\invoke-native-release.ps1 -PreflightOnly
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

Runtime активується в порядку `/opt/iros2j`, `/opt/imavros`, `/opt/vins`.
`native.env` і SSH credentials НЕ МОЖНА комітити.
