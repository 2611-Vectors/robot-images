#!/bin/sh
# Run by Paddock as root inside an Armbian image for a robot computer, as an image's last step,
# after its own setup: what a read-only root, NetworkManager owning the network, and a computer
# anyone could download can't have. The parts that check for a file first (cloud-init, netplan)
# do nothing where the base hasn't one. The masks name units of the base paddock.yaml pins (Armbian
# on Debian trixie): Paddock's inspection fails a mask of a unit the image doesn't have, which is
# how a misspelt name shows, so another base needs this list checked against its own units.
set -eu

# --- First boot: cloud-init (Ubuntu's) would make users, write the network, and grow the root at
# first boot; none of that belongs on an image built from Git. ---
if [ -d /etc/cloud ]; then
  touch /etc/cloud/cloud-init.disabled
fi

# --- The network: NetworkManager alone, with the address Paddock stamps. ---
# Netplan's files (DHCP on every port, for systemd-networkd) move aside, and systemd-networkd is
# masked. A program that would configure the network itself is its image's setup's to stop.
mkdir -p /etc/netplan.disabled
for file in /etc/netplan/*.yaml; do
  if [ -e "$file" ]; then
    mv "$file" /etc/netplan.disabled/
  fi
done
systemctl mask systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service

# --- A read-only root: Armbian's RAM logging (it would hide the kept journal), its first-boot
# resize (the data partition follows the root), and its first-run tasks (they write the root) off;
# what only writes the root masked (package lists, man pages, log rotation, dpkg backups); the
# journal is the log, so rsyslog goes. ---
if [ -f /etc/default/armbian-ramlog ]; then
  sed -i 's/^ENABLED=.*/ENABLED=false/' /etc/default/armbian-ramlog
fi
touch /root/.no_rootfs_resize
systemctl mask armbian-ramlog.service armbian-resize-filesystem.service armbian-firstrun.service \
  armbian-led-state.service
systemctl mask apt-daily.timer apt-daily-upgrade.timer man-db.timer logrotate.timer dpkg-db-backup.timer
systemctl mask rsyslog.service syslog.socket fake-hwclock-save.timer fake-hwclock-save.service
# With no clock battery, systemd starts the clock no earlier than this file's time: the build's.
touch /usr/lib/clock-epoch

# --- Logins: none on the board's own screen, no password that works (the base images' are public
# defaults), and SSH by key only (files/sshd.conf), with each drive's own host key. ---
rm -f /etc/systemd/system/getty@.service.d/override.conf /etc/systemd/system/serial-getty@.service.d/override.conf
systemctl mask getty@.service serial-getty@.service autovt@.service console-getty.service
mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nNAutoVTs=0\nReserveVT=0\n' >/etc/systemd/logind.conf.d/70-team.conf
# "*" matches no password, for every account that has one; a key still logs in ("!" would lock the
# account, which sshd refuses even for a key).
for shadow in /etc/shadow /etc/shadow-; do
  [ -f "$shadow" ] || continue
  awk -F: -v OFS=: '$2 !~ /^[*!]/ { $2 = "*" } { print }' "$shadow" >"$shadow.new"
  chmod --reference="$shadow" "$shadow.new"
  chown --reference="$shadow" "$shadow.new"
  mv -f "$shadow.new" "$shadow"
done
# The base image's host keys are in every copy of it, and published: each drive makes its own.
rm -f /etc/ssh/ssh_host_*
systemctl enable ssh-hostkey.service

# --- Checked: no password that works, and no console that logs in by itself. ---
if awk -F: '$2 !~ /^[*!]/ { found = 1 } END { exit !found }' /etc/shadow; then
  echo "a login still has a usable password (or none)" >&2
  exit 1
fi
if grep -rls -e '--autologin' /etc/systemd/system/*getty* 2>/dev/null; then
  echo "a console still logs in by itself" >&2
  exit 1
fi
