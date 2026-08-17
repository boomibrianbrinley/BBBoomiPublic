# Boomi systemd Service Installation

This document describes how to install and enable a **Boomi Runtime**
as a `systemd` service on a Linux server using an offline installation script.

The installer generates a `systemd` unit file that matches the official Boomi
service definition and enables the service to start automatically at boot.

---

## Overview

The installation script performs the following actions:

1. Creates a systemd service definition at  
   `/etc/systemd/system/boomi.service`
2. Parameterizes:
   - Linux user
   - Linux group
   - Boomi runtime installation path
3. Reloads the systemd daemon
4. Enables the service at boot
5. Starts the Boomi runtime service

No internet access is required.

---

## Supported Platforms

This procedure works on **any Linux distribution that uses `systemd`**, including:

- RHEL
- Debian
- Ubuntu
- Amazon Linux
- SUSE (systemd-based versions)

---

## Prerequisites

- Linux system running `systemd`
- Root or sudo access
- Boomi runtime already installed locally
- Boomi runtime control script present at:
  ```
  <runtime_path>/bin/atom
  ```
- Linux user and group already created for running Boomi

---

## Service Definition Details

The generated service file matches the official Boomi clustered runtime definition
with the following characteristics:

- **Description**: `LSB: Boomi Clustered Runtime`
- **Type**: `simple`
- **Restart Policy**: `always`
- **Timeout**: `5 minutes`
- **Resource Limits**:
  - `LimitNOFILE=65536`
  - `LimitNPROC=65536`
- **Lifecycle Commands**:
  - Start: `atom start`
  - Stop: `atom stop`
  - Reload: `atom restart`
- **RemainAfterExit**: `yes`

---

## Installation Script Usage

### Syntax

```bash
sudo ./install_boomi_systemd.sh -u <user> -p <runtime_path> [-g <group>] [-s <service_name>]
```

### Required Parameters

| Flag | Description |
|-----|------------|
| `-u` | Linux user that runs the Boomi service |
| `-p` | Boomi runtime path (directory containing `bin/atom`) |

### Optional Parameters

| Flag | Description | Default |
|-----|------------|---------|
| `-g` | Linux group for the service | Same as user |
| `-s` | systemd service name | `boomi` |

---

## Examples

### Standard Installation

```bash
sudo ./install_boomi_systemd.sh -u boomi -p /opt/boomi/runtime
```

Creates:
```
/etc/systemd/system/boomi.service
```

### Custom Service Name

```bash
sudo ./install_boomi_systemd.sh -u boomi -p /opt/boomi/runtime -s boomi-atom
```

Creates:
```
/etc/systemd/system/boomi-atom.service
```

---

## Post-Installation Operations

### Check Service Status

```bash
systemctl status boomi.service
```

### View Service Logs

```bash
journalctl -u boomi.service -n 200
```

### Restart the Service

```bash
systemctl restart boomi.service
```

---

## Notes

- The installer validates that the specified user and group exist before creating
  the service.
- If the Boomi runtime binary does not yet exist, the service file will still be
  created, but the initial service start may fail.
- The service is enabled for `multi-user.target`, ensuring it starts automatically
  during system boot.

---

## Uninstallation (Manual)

```bash
sudo systemctl stop boomi.service
sudo systemctl disable boomi.service
sudo rm /etc/systemd/system/boomi.service
sudo systemctl daemon-reload
```

---

## Troubleshooting

If the service fails to start:

1. Check service status:
   ```bash
   systemctl status boomi.service
   ```
2. Review logs:
   ```bash
   journalctl -u boomi.service
   ```
3. Verify permissions on the Boomi runtime directory
4. Ensure the Boomi user can execute the `atom` script

---
