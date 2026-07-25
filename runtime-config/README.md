# Runtime configuration

This directory is mounted as `/config` by the `manual` service.

Copy the configuration installed by the published package before the first
manual test:

```powershell
docker compose -f compose.runtime.yaml --profile manual cp `
  manual:/opt/vins/share/config_pkg/config/euroc/euroc_config.yaml `
  .\runtime-config\iVIN.yaml
```

Edit `iVIN.yaml` on the host. Rebuilding the Docker image is not required.
The EuRoC values are only a starting point and must not be treated as an iVIN
camera/IMU calibration.
