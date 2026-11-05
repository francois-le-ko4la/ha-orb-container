#!/bin/sh
# Fetch the upstream add-on scripts (orbforge/addon-orb) and patch them for Home Assistant Container:
# - entrypoint.sh: drop `printenv` (it dumps the MQTT password to the container logs);
# - mqtt.sh: wait for the broker, then republish MQTT discovery on every (re)connection.
# Nothing is overwritten if an upstream change breaks one of the patches.
set -e
cd "$(dirname "$0")"
URL=https://raw.githubusercontent.com/orbforge/addon-orb/refs/heads/main/docker
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$TMP/$1" "$URL/$1"
  else wget -qO "$TMP/$1" "$URL/$1"; fi
}
fetch entrypoint.sh
fetch mqtt.sh

sed -i '/^printenv$/d' "$TMP/entrypoint.sh"

sed -i \
  -e "/^echo \"\$mapping\" | while IFS='|' read/i publish_discovery() {" \
  -e '/^# mosquitto_pub -l keeps the connection open/i }\n\nwait_broker() {\n  until mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t orb_homeassistant/ping -n -q 0; do\n    echo "MQTT broker unreachable, retrying in 10s"; sleep 10\n  done\n}\n' \
  -e 's/^while true; do$/while true; do\n  wait_broker\n  publish_discovery/' \
  "$TMP/mqtt.sh"

fail() { echo "Upstream changed, patch not applied: $1" >&2; exit 1; }
! grep -q '^printenv$' "$TMP/entrypoint.sh" || fail "printenv"
grep -q '^publish_discovery() {' "$TMP/mqtt.sh" || fail "publish_discovery"
grep -q '^wait_broker() {' "$TMP/mqtt.sh" || fail "wait_broker"
[ "$(grep -c '^  publish_discovery$' "$TMP/mqtt.sh")" = 1 ] || fail "reconnect loop"
sh -n "$TMP/entrypoint.sh" && sh -n "$TMP/mqtt.sh"

install -m 755 "$TMP/entrypoint.sh" "$TMP/mqtt.sh" .
echo "entrypoint.sh and mqtt.sh updated and patched."
