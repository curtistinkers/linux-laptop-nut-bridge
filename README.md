# Dell Latitude E7440 Internal Battery to NUT Bridge

A native integration framework designed for the **Dell Latitude E7440**. This package translates the laptop's internal battery management system data directly into a standardized Network UPS Tools (NUT) pseudo-device called `internal-battery`.

By exposing live hardware capacity, voltage states, battery wear health metrics, and grid connection parameters to the local network stack, other servers, virtual machines, or network clients can monitor the host and execute graceful automated orchestrations when utility mains power is severed.

## Features

- **Zero-Dependency Core Logic**: Relies entirely on native, built-in GNU system shell infrastructure and core utilities (`sh`, `awk`, `grep`, `dd`).
- **Real-Time Hardware Metrics**: Automatically maps, extracts, and normalizes low-level kernel micro-unit values (μAh, μV) into standard electrical floating points (Ah, V, A).
- **Sandboxing**: Strict operational containment utilizing advanced `systemd` isolation policies.
- **Dynamic Variable Reporting**: Exposes battery wear calculation matrices, factory serial numbers, nominal profiles, and active charging statuses.

## Package Directory Architecture

```text
~/latitude-e7440-battery-nut-bridge/
├── DEBIAN/
│   ├── control       # Package metadata
│   ├── postinst      # Atomically patches configuration and configures systemd
│   └── prerm         # Safely strips custom modifications on removal
├── lib/
│   └── systemd
│       └── system
│           └── battery-nut-bridge.service   # Background hardware scraping loop
└── usr/
    └── libexec
        └── latitude-e7440-battery-nut-bridge
            └── power-handler.sh    # Battery data tracking shell script
```

## System Dependencies

When deployed via `apt`, the system configuration manager automatically ensures that the following pre-compiled distribution targets are active:

- `coreutils`
- `grep`
- `awk`
- `systemd`
- `nut-server` (Network UPS Tools - Monitoring Framework Daemon)
- `nut-client` (Network UPS Tools - Querying Utilities)

## Security Profile & Sandboxing

The `battery-nut-bridge.service` runs as a native background unit protected with strict security barriers. Even though it reads hardware telemetry nodes, it is isolated from mutating host processes:

- `ProtectSystem=strict`: The entire server filesystem layout is hard-locked as read-only.
- `ProtectHome=yes`, `ProtectKernelModules=yes`, `ProtectControlGroups=yes`: Blocks access to physical user homes, operational driver subsystems, and system tracking layers.
- `NoNewPrivileges=yes`: Strict process containment that prevents the utility from calling elevation binaries or cracking authorization boundaries.
- `RuntimeDirectory=battery-nut-bridge`: Restricts operational filesystem mutation explicitly to an ephemeral runtime cache folder located at `/run/battery-nut-bridge/`. Systemd manages the lifecycle of this folder automatically.

## Installation & Deployment

1. Compile the workspace structure cleanly on your host:

   ```bash
   dpkg-deb --build ~/latitude-e7440-battery-nut-bridge
   ```

2. Deploy the generated configuration archive using `apt`:

   ```bash
   sudo apt install ./latitude-e7440-battery-nut-bridge.deb
   ```

## Querying NUT Telemetry

Once installation completes, the background driver will automatically map to ibternal battery data. To review live metrics from the pseudo-UPS, use the standard NUT querying tool:

```bash
upsc internal-battery
```

### Output Example

```text
battery.charge: 100
battery.charge.full: 7.1
battery.charge.full.design: 7.2
battery.charge.now: 7.1
battery.current: 0.001
battery.cycles: 0
battery.health: 98.6%
battery.protection.high: 90
battery.protection.low: 50
battery.type: Li-poly
battery.voltage: 8.46
battery.voltage.nominal: 7.4
device.mfr: LGC-LGC3.6
device.model: DELL CJW7D09
device.serial: 46084
device.type: ups
ups.mfr: LGC-LGC3.6
ups.model: DELL CJW7D09
ups.serial: 46084
ups.status: OL
```

### Telemetry Field Guide

- `ups.status`: Reports current grid states (`OL` = Online/Utility Power, `OB` = On Battery/Mains Severed, `CHRG` = Actively Charging cell buffers, `LB` = Low Battery Warning under 15%).
- `battery.health`: Calculates active cell wear tracking based on the mathematical ratio between current fully chargeable capacity and initial factory design parameters.
- `battery.charge.now` / `full`: Normalized from raw hardware microampere-hours (μAh) into explicit standard Ampere-hours (Ah).

## Package Removal

To completely remove the NUT bridge, turn off background tasks, and completely clear the configuration parameters, run:

```bash
sudo apt purge latitude-e7440-battery-nut-bridge
```
