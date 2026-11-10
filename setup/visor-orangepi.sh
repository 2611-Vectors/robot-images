#!/bin/sh
# Run by Paddock as root inside plain Armbian for the Orange Pi 5 (paddock.yaml's image), after
# the files are in place and before setup/armbian-robot.sh: a computer that runs Visor, which the
# robot program installs and configures through Spotter's agent as it starts. This puts in what
# Armbian's minimal image lacks, Spotter's debian pack and Visor's part of the image, each from its
# own release, and the admin login.
set -eu
export DEBIAN_FRONTEND=noninteractive

# --- Packages from Armbian's own sources: NetworkManager (Paddock's network; the minimal image has
# systemd-networkd, which setup/armbian-robot.sh turns off) and chrony (the robot's clock). ---
apt-get update -q
apt-get install -y -q --no-install-recommends network-manager chrony
rm -rf /var/lib/apt/lists/*
# chrony's server is the robot controller, whose address is agent.json's (setup/chrony-conf.sh).
sh "$PADDOCK_CONFIG_DIR/setup/chrony-conf.sh" /etc/frc-spotter/agent.json \
  "$PADDOCK_CONFIG_DIR/files/visor/chrony.conf" >/etc/chrony/chrony.conf
chmod 0644 /etc/chrony/chrony.conf
systemctl enable NetworkManager.service chrony.service cpu-performance.service

# --- Spotter's debian pack, from the source of the agent's own release (paddock.yaml downloads it,
# and it stays where it's put, as Paddock's inspection checks): the computer's own health, CPU, heat,
# memory, disk, link, USB and clock, as Spotter's alerts on the robot. Installed with the image,
# root's, as the agent trusts nothing else there; the robot pushes only Visor's pack. Its drive
# values need an NVMe drive and a root timer (its README), so on a computer without one they're
# unavailable. ---
spotter_source=/usr/local/share/frc-spotter/source.tar.gz
unpacked=$(mktemp -d)
# Only the catalog's packs/debian: "*" stops at a "/", so the agent's test packs stay out.
tar -xzf "$spotter_source" -C "$unpacked" --wildcards --no-wildcards-match-slash 'frc-spotter-*/packs/debian/*'
install -d -o root -g root -m 0755 /etc/frc-spotter/packs
cp -r "$unpacked"/frc-spotter-*/packs/debian /etc/frc-spotter/packs/
rm -rf "$unpacked"
chown -R root:root /etc/frc-spotter/packs/debian
chmod -R go-w /etc/frc-spotter/packs/debian
[ -f /etc/frc-spotter/packs/debian/pack.yaml ] || { echo "Spotter's source has no packs/debian/pack.yaml" >&2; exit 1; }

# --- Visor, from the release paddock.yaml downloads: its os/ folder is what the image needs for it,
# at the paths a package's files take (Visor's spotter/visor/README.md lists them): its account, its
# folder (the agent's to write: Visor's pack installs into it), its unit, and the agent's drop-in and
# polkit rule for Visor's pack. Then the program, so the computer runs `visor cameras` and `visor
# record --device` before any robot has configured it (lens calibration). The robot replaces the
# program with its own version; `visor` on the PATH (files/visor/visor, root's) runs whichever is in
# place, and never as root. The release stays at /opt/visor/.release.tar.gz, as paddock.yaml's step
# put it (Paddock's inspection checks each step's file is in the image). What's the board's own, the
# cores Visor runs on and its folder kept on the data partition, is files/visor/visor-service.conf
# and paddock.yaml's. ---
release=/opt/visor/.release.tar.gz
unpacked=$(mktemp -d)
tar -xzf "$release" -C "$unpacked" ./visor ./os
[ -f "$unpacked/os/usr/lib/systemd/system/visor.service" ] || { echo "the Visor release has no os/: pin a newer one" >&2; exit 1; }
cp -r "$unpacked/os/." /
systemd-sysusers visor.conf
systemd-tmpfiles --create visor.conf
install -m 0755 -o frc-spotter -g frc-spotter "$unpacked/visor" /opt/visor/visor
rm -rf "$unpacked"
/opt/visor/visor version
systemctl enable visor.service

# --- The admin login: your team's SSH keys (keys/authorized_keys), sudo without a password, as
# there is none. "*" matches no password; "!" would lock the account, which sshd refuses even for a
# key. ---
useradd --create-home --shell /bin/bash --groups sudo,systemd-journal,video admin
usermod -p '*' admin
install -d -m 0700 -o admin -g admin /home/admin/.ssh
install -m 0600 -o admin -g admin "$PADDOCK_CONFIG_DIR/keys/authorized_keys" /home/admin/.ssh/authorized_keys
printf 'admin ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/admin
chmod 0440 /etc/sudoers.d/admin
visudo -cf /etc/sudoers.d/admin
