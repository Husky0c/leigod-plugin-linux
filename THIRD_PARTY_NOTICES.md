# Third-party notices

The repository-level MIT license applies only to code and documentation
originally authored for this compatibility project.

## Leigod material

The following material is supplied by, derived from, or interoperates with the
Leigod SteamDeck plugin and is **not relicensed under MIT**:

- `acc-gw.router.amd64` (downloaded during installation/build);
- `ipdatacloud_country.xdb` (downloaded during installation/build);
- compatibility configuration under `opt/leigod/config/`;
- SteamDeck plugin process behavior adapted by
  `opt/leigod/steamdeck_acc_monitor.sh`.

All rights in Leigod names, services, binaries, databases, configuration and
upstream-derived material remain with their respective owners. No permission
to redistribute those assets is granted by this repository.

Before publishing a binary package or archive that embeds downloaded Leigod
assets, obtain explicit redistribution permission from the relevant
rightsholder. The project's automated GitHub Release contains source code only;
end users download the official assets themselves and the installer verifies
their pinned SHA-256 digests.
