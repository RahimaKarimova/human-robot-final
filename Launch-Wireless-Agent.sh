#!/usr/bin/env bash
# Run on Reachy Mini Wireless after copying/extracting the prepared agent package.
set -eu
if [ "$#" -lt 1 ]; then
  echo 'Usage: bash Launch-Wireless-Agent.sh /private/path/current.robot.json [--gestures]'
  exit 2
fi
agent_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$1" in
  /*) session_config="$1" ;;
  *) session_config="$PWD/$1" ;;
esac
shift
if [ ! -r "$session_config" ]; then
  echo 'The private robot session configuration is missing or unreadable.'
  exit 2
fi
umask 077
cd "$agent_root/services/controller"
exec "${REACHY_AGENT_PYTHON:-python3}" -m echo_controller.robot_worker --config "$session_config" "$@"
