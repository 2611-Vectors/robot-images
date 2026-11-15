# Notice

These images hold software under the GNU General Public License and other licenses. Each release's
`manifest.json` names every base image and package in them by URL and SHA-256.

- **Armbian for the Orange Pi 5,** built on Debian and the Linux kernel (mostly GPL): the image
  `paddock.yaml`'s `from.url` names, which PhotonVision builds
  (https://github.com/PhotonVision/opi-image-generator at that release) from Armbian's source at
  https://github.com/armbian/build, with the kernel's at
  https://github.com/armbian/linux-rockchip and the bootloader (U-Boot, GPL) taken from
  https://github.com/Joshua-Riek/ubuntu-rockchip.
- **Spotter's agent** (MIT): the package `paddock.yaml` names, with its source at
  https://github.com/mikegrundvig/frc-spotter at that release; it bundles a Java runtime (GPL with
  the Classpath Exception).
- **Visor** (GPL-3.0, and NAPA within it): the release `paddock.yaml` downloads, and
  whichever release the robot installs over it, with its source at
  https://github.com/mikegrundvig/frc-visor at that release.

Keep this current when you change a base or add a package. Pass it on with the images when you give
them to anyone.
