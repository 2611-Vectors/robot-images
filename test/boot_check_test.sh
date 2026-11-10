#!/bin/bash
# test/boot_check.sh, the image's boot check, against stand-ins for what it reads in the booted
# image: systemd's view of the agent's unit, the agent's listening socket (/proc/net/tcp6), and
# Visor's program run as the visor user. Each row is a board, and whether the check passes it.
# Run it from anywhere: test/boot_check_test.sh
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

fail() {
  echo "FAIL: $*"
  failed=1
}

# A booted image as the check sees it, in $work/$1: the agent's unit in STATE (ActiveState/SubState,
# its restarts), whether the agent listens on Spotter's port, and what `visor version` does.
board() {
  local dir=$work/$1 state=$2 restarts=$3 listens=$4 visor=$5
  mkdir -p "$dir/bin" "$dir/proc/net"
  # systemctl show frc-spotter.service, as systemd answers it.
  cat >"$dir/bin/systemctl" <<EOF
#!/bin/sh
printf 'LoadState=%s\nActiveState=%s\nSubState=%s\nNRestarts=%s\n' $state $restarts
EOF
  # runuser -u visor -- /opt/visor/visor version
  case $visor in
    runs) printf '#!/bin/sh\necho "visor 2026.11.9 (version ID 20261109)"\n' >"$dir/bin/runuser" ;;
    fails) printf '#!/bin/sh\necho "visor: cannot execute binary file" >&2\nexit 126\n' >"$dir/bin/runuser" ;;
    no-user) printf '#!/bin/sh\necho "runuser: user visor does not exist" >&2\nexit 1\n' >"$dir/bin/runuser" ;;
  esac
  chmod +x "$dir/bin/systemctl" "$dir/bin/runuser"
  # The kernel's TCP sockets: 5808 (16B0) listening (0A) on any address, or nothing.
  printf '  sl  local_address                         remote_address                        st\n' >"$dir/proc/net/tcp6"
  if [[ $listens == yes ]]; then
    printf '   0: 00000000000000000000000000000000:16B0 00000000000000000000000000000000:0000 0A\n' >>"$dir/proc/net/tcp6"
  fi
  printf '  sl  local_address rem_address   st\n' >"$dir/proc/net/tcp"
}

# Each row: the board, the agent's unit (LoadState ActiveState SubState), its restarts, whether it
# listens, what `visor version` does, and what the check must say ("passes" for a board it passes).
rows=(
  "good|loaded active running|0|yes|runs|passes"
  "agent-failed|loaded failed failed|5|no|runs|frc-spotter.service isn't running"
  "agent-restarting|loaded activating auto-restart|3|no|runs|frc-spotter.service isn't running"
  "agent-missing|not-found inactive dead|0|no|runs|frc-spotter.service isn't running"
  "agent-crashed-once|loaded active running|1|yes|runs|frc-spotter.service has restarted 1 time(s)"
  "agent-not-listening|loaded active running|0|no|runs|the agent isn't listening on port 5808"
  "visor-fails|loaded active running|0|yes|fails|visor version doesn't run as the visor user"
  "no-visor-user|loaded active running|0|yes|no-user|visor version doesn't run as the visor user"
)
for row in "${rows[@]}"; do
  IFS='|' read -r name state restarts listens visor said <<<"$row"
  board "$name" "$state" "$restarts" "$listens" "$visor"
  output=$(PATH=$work/$name/bin:$PATH BOOT_CHECK_PROC=$work/$name/proc BOOT_CHECK_WAIT=2 \
    bash "$repo/test/boot_check.sh" 2>&1)
  status=$?
  if [[ $said == passes ]]; then
    [[ $status == 0 ]] || fail "$name: the check should pass, but said: $output"
    continue
  fi
  [[ $status != 0 ]] || fail "$name: the check passed, but should say '$said'"
  [[ $output == *"$said"* ]] || fail "$name: the check should say '$said', but said: $output"
done

if ((failed)); then
  exit 1
fi
echo "boot check: ok"
