Using Docker, deploy Geant4 rapidly on Linux, macOS, or Windows and run the default example simulation.

Requirements:
- Docker with the modern Compose plugin.

Commands:

```bash
docker compose build
docker compose up
```

The image is based on Ubuntu 22.04 and builds Geant4 10.7.4, Xerces-C 3.2.2, and CADMesh during `docker compose build`.

Shared folders:
- `interface/` is mounted read-only at `/interface` for user scripts and future customization.
- `output/` is mounted at `/work/output` for simulation output.

The default `docker-compose.yml` command clones and runs `COSMIC_RAY_THUNDERSTORM-Geant4`. Edit that command to build and run a different Geant4 project.

The old Docker-specific Geant4 installer was moved to `OLD/`; Docker now uses the repository's unified Ubuntu Geant4 installer.
