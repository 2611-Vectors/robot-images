# Robot computer images

Based on frc-paddock-starter by Mike Grundvig; see LICENSE.

Your robot's computers, managed in Git and built by
[Paddock](https://github.com/mikegrundvig/frc-paddock). This repository says what each image is (a
base image and what's added to it) and which computers get it. Paddock builds one image per computer,
stamped with its hostname and address, and publishes them as a release of this repository. To change
a computer, change this repository and cut a release; to replace a broken one, flash its image onto a
drive.

The example is a vision computer: an Orange Pi 5 running [Visor](https://github.com/mikegrundvig/frc-visor),
AprilTag vision with NAPA, from plain Armbian with [Spotter](https://github.com/mikegrundvig/frc-spotter)'s
agent. The robot program installs and configures Visor on it through the agent as it starts, so the
image holds nothing of a robot's, and a spare flashed from it just works. Its root is read-only, so a
power cut can't damage it; SSH takes keys only, and no password works.

## Start

1. **Use this template** (the green button on GitHub) to make your team's repository.
2. **Set your computers' addresses** in `paddock.yaml`: `10.TE.AM.11/24` and gateway `10.TE.AM.4`
   for team 1234 are `10.12.34.11/24` and `10.12.34.4`. Add a computer for each board. Also your
   robot controller's address, `10.TE.AM.2`, in `files/visor/agent.json` (Spotter takes the robot's
   pushes and actions from it alone) and `files/visor/chrony.conf` (the clock Visor stamps frames
   with).
3. **Pick your versions:** the base image for your board from
   [Armbian's downloads](https://www.armbian.com/orange-pi-5/) (`from.url`, a minimal image, with
   its `.sha` file's SHA-256), Spotter's agent from
   [its releases](https://github.com/mikegrundvig/frc-spotter/releases) (the `package` step), and a
   Visor release from [its releases](https://github.com/mikegrundvig/frc-visor/releases) (the
   `download` step; each release lists its files' SHA-256). The robot installs its own Visor over the
   image's, so that one only needs to run.
4. **Add your SSH public keys** to `keys/authorized_keys`, one per line, to log in as `admin`, with
   sudo. Public keys only: the images may be public. With none, nobody can log in.
5. **Build.** Run *Images* from the Actions tab with a release name, such as `images-2027.1`, or push
   a tag of that name:

   ```bash
   git tag images-2027.1 && git push origin images-2027.1
   ```

   The release holds each computer's `.img.xz`, `SHA256SUMS`, `manifest.json` (what's in each image,
   by URL and SHA-256), and `NOTICE.md`.
6. **Flash** each computer's image onto its drive (Raspberry Pi Imager, or Rufus) after checking it
   against `SHA256SUMS`.

The images are built on GitHub's ARM runners, which are free for public repositories; a private one
needs paid ARM runners.

## What's here

| Path | What |
|---|---|
| `paddock.yaml` | The images (each a base and its steps) and the computers stamped from them. Paddock's README says every key |
| `setup/visor-orangepi.sh` | The image's own setup: NetworkManager and chrony, Visor's account, program and unit, and the admin login |
| `setup/armbian-robot.sh` | Its last step, for any robot computer from an Armbian base: NetworkManager owning the network, a read-only root's needs, no default passwords. Each part says why |
| `files/` | Files the steps copy in: SSH's settings and each drive's own host key, NetworkManager's, the journal's, e2fsck's; `files/visor/`: Spotter's settings, what Visor's pack may do (write `/opt/visor`, restart Visor), Visor waiting for its configuration, chrony's, the CPU at full clock; `files/spotter-packs/debian/`: Spotter's catalog pack for the computer's own health, copied from Spotter's release the image installs (copy it again when you move to another) |
| `keys/authorized_keys` | Your team's SSH public keys |
| `NOTICE.md` | What software your images hold and where its source is: keep it current when you change the base or add packages |

**Another kind of computer** (a Raspberry Pi running something else, say) is another entry in
`images:` with its own base and steps, and its computers name it.

## License

MIT: see `LICENSE`.
