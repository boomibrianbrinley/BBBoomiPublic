# BBBoomiPublic

A collection of public Boomi reference tooling, installer scripts, and platform utilities.

## Contents

| Folder | Contents |
|---|---|
| [`boomi/installers/`](boomi/installers/) | Install/autostart/restart scripts for running a Boomi Runtime as a Linux `systemd` or macOS `launchd` service, plus a `sudoers.d` drop-in. See its [README](boomi/installers/README.md) for which script to use. |
| [`boomi/scripts/date-format-normalizer/`](boomi/scripts/date-format-normalizer/) | A JavaScript snippet for a Boomi Data Process shape that detects a date string's format and returns its matching date mask. |
| [`boomi/browser-toolkit/`](boomi/browser-toolkit/) | An unofficial browser script that adds quality-of-life features to the Boomi AtomSphere UI (Build, Extension Designer, Deploy & Packaging, Process Reporting). |
| [`boomi-runtime-execution-log-footprint/`](boomi-runtime-execution-log-footprint/) | Bash and Python tools that analyze disk usage by Boomi process execution logs, to help tune logging levels and process design. |
| [`CAM/`](CAM/) | Claude Code plugin packages for Boomi tooling (`boomi-cam`, `mashery-apim`). |
| [`CICD/`](CICD/) | A packaged Boomi CI/CD CLI tool (`boomi_cicd`, with Azure Pipelines/Bitbucket Pipelines support) and an example Azure Pipelines YAML. |
| [`Southern/`](Southern/) | A Grafana observability package (alerts + dashboards) for Boomi OpenTelemetry data. |

## Contributing

Feel free to submit issues, feature requests, or pull requests.
