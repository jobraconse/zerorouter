#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Print fysieke netwerkinterfaces, uitsluitend loopback en bekende virtuele namen (docker, veth, br-, virbr, vmnet, ...)
for iface_path in /sys/class/net/*; do
  iface=$(basename "$iface_path")

  # altijd overslaan
  [ "$iface" = "lo" ] && continue

  # expliciet uitsluiten van bekende virtuele/bridge/docker-prefixes
  case "$iface" in
    docker*|docker0|veth*|br-*|virbr*|vmnet*|tap*|tun*|ifb*|macvlan* )
      continue
      ;;
  esac

  # Als er een apparaat-entry bestaat is het doorgaans een fysieke interface
  if [ -e "$iface_path/device" ]; then
    echo "$iface"
  fi
done
