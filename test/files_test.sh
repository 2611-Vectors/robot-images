#!/bin/bash
# The lines in files/ that the boards depend on, checked before an image is built
# (.github/workflows/images.yml). Run it from anywhere: test/files_test.sh
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failed=0

fail() {
  echo "FAIL: $*"
  failed=1
}

# A file, and a line it must have (or must not have), with why. Comments don't count.
must_have=(
  "files/visor/chrony.conf|rtcsync|without it chrony never clears the kernel's unsynchronised flag, and the robot drops every Visor frame"
  "files/frc-spotter.conf|After=opt-visor.mount var-lib-frc\\x2dspotter.mount|the agent waits for the kept paths' mounts when they work"
  "files/visor/visor-service.conf|RequiresMountsFor=/opt/visor|Visor runs only from the kept /opt/visor"
  "files/visor/visor-service.conf|CPUAffinity=4-7|Visor runs on the RK3588's fast cores, which are this board's to name"
)
must_not_have=(
  "files/frc-spotter.conf|RequiresMountsFor=|a failed data partition would stop the agent, and the board would go dark"
  "files/frc-spotter.conf|ReadWritePaths=|what the agent may write is its own unit's and Visor's release's, not a copy here"
  "setup/visor-orangepi.sh|ln -s /opt/visor/visor /usr/local/bin/visor|root's PATH would reach a program the agent can write"
)

lines_of() {
  grep -Ev '^[[:space:]]*(#|$)' "$repo/$1"
}

for row in "${must_have[@]}"; do
  IFS='|' read -r file line why <<<"$row"
  lines_of "$file" | grep -qxF -- "$line" || fail "$file has no line '$line': $why"
done
for row in "${must_not_have[@]}"; do
  IFS='|' read -r file line why <<<"$row"
  if lines_of "$file" | grep -qF -- "$line"; then
    fail "$file has '$line': $why"
  fi
done

# The visor on the PATH: refuses root before it runs anything; anyone else gets /opt/visor/visor.
wrapper=$repo/files/visor/visor
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
for row in "0|refuses|not as root" "1000|runs|/opt/visor/visor"; do
  IFS='|' read -r uid what text <<<"$row"
  printf '#!/bin/sh\necho %s\n' "$uid" >"$fake/id"
  chmod +x "$fake/id"
  output=$(PATH=$fake:$PATH "$wrapper" cameras 2>&1)
  status=$?
  [[ $status != 0 ]] || fail "visor as uid $uid exited 0 without a program in /opt/visor"
  [[ $output == *"$text"* ]] || fail "visor as uid $uid should have $what ('$text'), but said: $output"
done
[[ -x $wrapper ]] || fail "files/visor/visor isn't executable"
yq -e '.images.visor.steps[] | select(.to == "/usr/local/bin/visor") | .mode == "0755"' "$repo/paddock.yaml" >/dev/null 2>&1 ||
  fail "paddock.yaml doesn't install files/visor/visor as /usr/local/bin/visor, mode 0755"

# The robot controller's address is files/visor/agent.json's alone: chrony's server line is written
# from it at build time (setup/chrony-conf.sh), so no other file the image is built from names it.
controller=$(sed -n 's/.*"controller"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$repo/files/visor/agent.json")
[[ -n $controller ]] || fail "files/visor/agent.json names no controller"
others=$(grep -rlwF -- "$controller" "$repo/files" "$repo/setup" "$repo/paddock.yaml" | grep -vxF "$repo/files/visor/agent.json")
[[ -z $others ]] || fail "the controller's address, $controller, is written outside files/visor/agent.json: ${others//"$repo/"/}"

# chrony's configuration from agent.json: each row an agent.json, and the server line it must give
# (or what the script must say when it refuses).
for row in \
  '{"controller": "10.12.34.2"}|server 10.12.34.2 port 5806 iburst minpoll -3 maxpoll 0' \
  '{"team": 1234, "controller":"10.12.34.2"}|server 10.12.34.2 port 5806 iburst minpoll -3 maxpoll 0' \
  '{"team": 1234}|names no controller' \
  '{"controller": "roborio.local"}|isn'"'"'t an IPv4 address'; do
  IFS='|' read -r json said <<<"$row"
  printf '%s\n' "$json" >"$fake/agent.json"
  output=$(sh "$repo/setup/chrony-conf.sh" "$fake/agent.json" "$repo/files/visor/chrony.conf" 2>&1)
  status=$?
  if [[ $said == server* ]]; then
    [[ $status == 0 ]] || fail "chrony-conf.sh refused $json: $output"
    grep -qxF -- "$said" <<<"$output" || fail "chrony-conf.sh gave no line '$said' for $json"
    [[ $output != *@CONTROLLER@* ]] || fail "chrony-conf.sh left @CONTROLLER@ in for $json"
  else
    [[ $status != 0 ]] || fail "chrony-conf.sh took $json"
    [[ $output == *"$said"* ]] || fail "chrony-conf.sh should say '$said' for $json, but said: $output"
  fi
done

if ((failed)); then
  exit 1
fi
echo "files: ok"
