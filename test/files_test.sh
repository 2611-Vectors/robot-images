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
  "files/visor/frc-spotter-visor.conf|ReadWritePaths=-/opt/visor -/var/lib/frc-spotter|the agent must start when the data partition doesn't mount"
  "files/visor/frc-spotter-visor.conf|After=opt-visor.mount var-lib-frc\\x2dspotter.mount|the agent waits for the kept paths' mounts when they work"
  "files/visor/visor-service.conf|RequiresMountsFor=/opt/visor|Visor runs only from the kept /opt/visor"
)
must_not_have=(
  "files/visor/frc-spotter-visor.conf|RequiresMountsFor=|a failed data partition would stop the agent, and the board would go dark"
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

if ((failed)); then
  exit 1
fi
echo "files: ok"
