# BBBoomiPublic

This repository contains a collection of tools, scripts, and configuration files for managing and analyzing Boomi AtomSphere runtimes, particularly in Linux environments.

## Directory Overview

- **`LinuxServiceDefinitionInstaller/`**: Contains a Bash script to install and enable a Boomi Runtime as a `systemd` service.
- **`boomi-runtime-execution-log-footprint/`**: Tools to analyze disk usage by Boomi processes through their execution logs (Bash version).
- **`cicd/`**: Contains Boomi CI/CD CLI tools.
- **`kw/`**: Contains the Python version of the Boomi Process Log Space Analyzer and related documentation.
- **`sudoers/`**: Sample `sudoers` configurations for Boomi service management.

## Root Level Files

- **`boomi.service` / `boomi-cluster.service`**: Example `systemd` unit files for standalone and clustered Boomi runtimes.
- **`boomi.sudoers`**: Example sudoers configuration.
- **`restart-systemd.sh`**: A script to manage the restart of Boomi services via `systemd`.
- **`UpdatedDateFormat.js`**: A JavaScript utility for date format pattern matching.
- **`pipeline-example.yaml`**: An example Azure DevOps pipeline configuration for Boomi deployments.
- **`RandomTurbineData.csv`**: Sample data file.

## Key Tools

### Boomi Process Log Space Analyzer
Available in both Bash and Python, this tool helps identify which Boomi processes are consuming the most disk space, allowing for better log management and process optimization.

### Linux Service Installer
A script that automates the creation of a `systemd` service for Boomi, ensuring it starts correctly on boot and can be managed using standard Linux service tools.
