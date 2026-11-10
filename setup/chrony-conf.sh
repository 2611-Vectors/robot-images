#!/bin/sh
# Prints chrony's configuration for a Visor computer: the template (files/visor/chrony.conf) with
# @CONTROLLER@ replaced by the robot controller's address from Spotter's agent.json, which is that
# address's one place in this repository. setup/visor-orangepi.sh runs it as the image is built;
# test/files_test.sh runs it on its own rows.
#
#   setup/chrony-conf.sh AGENT_JSON TEMPLATE
set -eu
agent=$1
template=$2

# agent.json's "controller", the one value read from it; jq isn't in the base image.
controller=$(sed -n 's/.*"controller"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$agent")
if [ -z "$controller" ]; then
  echo "$agent names no controller: give it the robot controller's address, 10.TE.AM.2" >&2
  exit 1
fi
if ! printf '%s\n' "$controller" | grep -Eqx '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
  echo "$agent's controller, '$controller', isn't an IPv4 address: chrony needs 10.TE.AM.2" >&2
  exit 1
fi
if ! grep -q '@CONTROLLER@' "$template"; then
  echo "$template has no @CONTROLLER@ for the controller's address" >&2
  exit 1
fi
sed "s/@CONTROLLER@/$controller/g" "$template"
