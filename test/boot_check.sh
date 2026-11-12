#!/bin/bash
# The image's boot check (paddock.yaml's boot.check): Paddock's workflow runs it as root, with bash,
# inside a copy of the image booted in a container, once its boot has finished. It passes a board
# the robot can use as it starts: Spotter's agent up, the robot's way in, and Visor's program
# running on this image as its own user. Each failure is named, and any fails the build.
#
# visor.service itself waits for the robot's configuration (Visor's unit), so it doesn't start here.
# BOOT_CHECK_PROC and BOOT_CHECK_WAIT (seconds) are for test/boot_check_test.sh.
set -u
proc=${BOOT_CHECK_PROC:-/proc}
wait=${BOOT_CHECK_WAIT:-60}
# Spotter's agent's port: agent.json sets none, so it's the agent's default.
port=5808
failed=0

fail() {
  echo "boot check: $*" >&2
  failed=1
}

# A property of the agent's unit, as systemd has it.
agent() {
  systemctl show frc-spotter.service --property="$1" | sed -n "s/^$1=//p"
}

# Whether anything listens on TCP port $port, on any address (the kernel's tables: no ss here).
listening() {
  local hex
  hex=$(printf '%04X' "$port")
  awk -v port=":$hex" '$4 == "0A" && substr($2, length($2) - 4) == port { found = 1 } END { exit !found }' \
    "$proc/net/tcp" "$proc/net/tcp6" 2>/dev/null
}

# Visor's program, the one the image put in /opt/visor, run as the account its unit runs it as.
if ! said=$(runuser -u visor -- /opt/visor/visor version 2>&1); then
  fail "visor version doesn't run as the visor user: $said"
elif [[ $said != "visor "* ]]; then
  fail "visor version said '$said', not its version"
else
  echo "boot check: $(head -n 1 <<<"$said")"
fi

# The agent: running, listening, and not restarted on the way, since a
# crash it came back from is a crash on the board too.
up=no
for ((i = 0; i < wait; i++)); do
  if [[ $(agent ActiveState) == active && $(agent SubState) == running ]] && listening; then
    up=yes
    break
  fi
  sleep 1
done
state="$(agent LoadState) $(agent ActiveState) $(agent SubState)"
if [[ $(agent ActiveState) != active || $(agent SubState) != running ]]; then
  fail "frc-spotter.service isn't running after ${wait}s: $state"
elif [[ $up != yes ]]; then
  fail "frc-spotter.service runs, but the agent isn't listening on port $port after ${wait}s"
elif [[ $(agent NRestarts) != 0 ]]; then
  fail "frc-spotter.service has restarted $(agent NRestarts) time(s) since the boot"
else
  echo "boot check: frc-spotter.service is running and listening on port $port"
fi

exit "$failed"
