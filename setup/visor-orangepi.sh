#!/bin/sh
# Run by Paddock as root inside plain Armbian for the Orange Pi 5 (paddock.yaml's image), after
# the files are in place and before setup/armbian-robot.sh: a computer that runs Visor, which the
# robot program installs and configures through Spotter's agent as it starts. This puts in what
# Armbian's minimal image lacks, Spotter's debian pack, Visor's account and unit, and the admin
# login.
set -eu
export DEBIAN_FRONTEND=noninteractive

# --- Packages from Armbian's own sources: NetworkManager (Paddock's network; the minimal image has
# systemd-networkd, which setup/armbian-robot.sh turns off) and chrony (the robot's clock). ---
apt-get update -q
apt-get install -y -q --no-install-recommends network-manager chrony
rm -rf /var/lib/apt/lists/*
install -m 0644 "$PADDOCK_CONFIG_DIR/files/visor/chrony.conf" /etc/chrony/chrony.conf
systemctl enable NetworkManager.service chrony.service cpu-performance.service

# --- Spotter's debian pack (files/spotter-packs/debian, Spotter's catalog's at the agent's
# version): the computer's own health, CPU, heat, memory, disk, link, USB and clock, as Spotter's
# alerts on the robot. Installed with the image, root's, as the agent trusts nothing else there; the
# robot pushes only Visor's pack. Its drive values need an NVMe drive and a root timer (its README),
# so on a computer without one they're unavailable. ---
install -d -o root -g root -m 0755 /etc/frc-spotter/packs
cp -r "$PADDOCK_CONFIG_DIR/files/spotter-packs/debian" /etc/frc-spotter/packs/
chown -R root:root /etc/frc-spotter/packs/debian
chmod -R go-w /etc/frc-spotter/packs/debian

# --- Visor: its account, its folder (the agent's to write: Visor's pack installs into it), and the
# program and unit from the release paddock.yaml downloads, so the computer runs `visor cameras`
# and `visor record --device` before any robot has configured it (lens calibration). The robot
# replaces the program with its own version; `visor` on the PATH is whichever is in place. ---
useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --groups video visor
release=/opt/visor/.release.tar.gz
unpacked=$(mktemp -d)
tar -xzf "$release" -C "$unpacked" ./visor ./visor.service
install -m 0755 -o frc-spotter -g frc-spotter "$unpacked/visor" /opt/visor/visor
install -m 0644 "$unpacked/visor.service" /etc/systemd/system/visor.service
ln -s /opt/visor/visor /usr/local/bin/visor
rm -rf "$unpacked" "$release"
chown frc-spotter:frc-spotter /opt/visor
chmod 0755 /opt/visor
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
