# Linux Laptop NUT Bridge

A lightweight, sandboxed integration framework that exposes a Linux laptop's internal battery telemetry to Network UPS Tools (NUT). It dynamically scans and adapts to diverse laptop hardware layouts, translating ACPI metrics into a `[battery]` pseudo-UPS NUT device.

## Directory Structure

```text
~/linux-laptop-nut-bridge/
├── DEBIAN/
│   ├── control       # Package metadata and system dependencies
│   ├── postinst      # Patches NUT config and schedules the systemd timer
│   └── prerm         # Stops services and strips configurations on removal
├── lib/
│   └── systemd
│       └── system
│           ├── linux-laptop-nut-bridge.service  # Oneshot telemetry metrics scraper
│           └── linux-laptop-nut-bridge.timer    # Core timer (runs every 2 seconds)
└── usr/
    └── libexec
        └── linux-laptop-nut-bridge
            └── battery-nut-sync.sh        # Universal path parsing script
```

## System Dependencies

Automatically pulled during installation:

* `coreutils`, `grep`, `awk`, `systemd`
* `nut-server`
* `nut-client`

## Sandbox Isolation

The `linux-laptop-nut-bridge.service` utilizes strict systemd security confinement:

* `ProtectSystem=strict` blocks total filesystem modification.
* `NoNewPrivileges=yes` prevents process privilege elevation.
* `RuntimeDirectory=linux-laptop-nut-bridge` confines all transient file operations strictly to an ephemeral, root-allocated memory space at `/run/linux-laptop-nut-bridge/`.
* `RuntimeDirectoryPreserve=yes` ensures the tracked metrics remain in memory between the timer execution intervals.

## Build and Installation

1. Compile the workspace structure cleanly on your host machine:

   ```bash
   dpkg-deb --build ~/linux-laptop-nut-bridge
   ```

2. Deploy the generated configuration archive using `apt`:

   ```bash
   sudo apt install ./linux-laptop-nut-bridge.deb
   ```

## Verifying NUT Telemetry

Query the virtual device status across the network layer by running:

```bash
upsc battery
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
battery.voltage: 8.456
battery.voltage.nominal: 7.4
device.mfr: LGC-LGC3.6
device.model: DELL CJW7D09
device.serial: 46084
device.type: ups
driver.debug: 0
driver.flag.allow_killpower: 0
driver.name: dummy-ups
driver.parameter.mode: dummy
driver.parameter.pollinterval: 2
driver.parameter.port: /run/linux-laptop-nut-bridge/internal-battery-sync.status
driver.parameter.synchronous: auto
driver.state: updateinfo
driver.version: 2.8.1
driver.version.internal: 0.18
ups.mfr: LGC-LGC3.6
ups.model: DELL CJW7D09
ups.serial: 46084
ups.status: OL
```

## Package Purge

To completely stop background tasks and cleanly strip out the custom configuration, execute:

```bash
sudo apt purge linux-laptop-nut-bridge
```
