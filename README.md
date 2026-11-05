# ha-orb-container

> [!NOTE]
> This is a personal, unofficial adaptation. I am not affiliated with Orb Forge
> and do not work on the Orb project. For the official sensor and add-on, see
> [orb.net](https://orb.net) and
> [orbforge/addon-orb](https://github.com/orbforge/addon-orb). Please report
> issues with this setup here, not to Orb.

Run the [Orb](https://orb.net) sensor next to **Home Assistant Container** (no
Supervisor, no add-on store) and get its scores in Home Assistant through MQTT
discovery.

Orb's official [Home Assistant add-on](https://github.com/orbforge/addon-orb)
only installs on Home Assistant OS or Supervised. Its Docker image,
`orbforge/orb-ha`, works anywhere: this repository runs that image with Docker
Compose and patches its two scripts for a standalone setup.

## How it works

| Piece                      | Role                                                                       |
| -------------------------- | -------------------------------------------------------------------------- |
| `orbforge/orb-ha`          | Official image: Orb sensor plus `mosquitto-clients`, `jq` and `curl`       |
| `entrypoint.sh`, `mqtt.sh` | Upstream add-on scripts, mounted over the ones in the image after patching |
| `update_scripts.sh`        | Downloads the upstream scripts and applies the patches below               |

Every `MQTT_PAUSE` seconds, `mqtt.sh` runs `orb summary` and publishes the
result to `orb_homeassistant/status`. Home Assistant discovers the sensors from
retained messages under `homeassistant/sensor/orb_*/config`.

### Patches

| Upstream behavior                                                                                                                | Patched behavior                                  |
| -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `entrypoint.sh` runs `printenv`, which writes the MQTT password to the container logs                                            | `printenv` removed                                |
| Discovery is published once, at startup; if the broker is not up yet, the sensors never appear                                   | The script waits for the broker before publishing |
| A broker restart drops retained messages when they are kept in RAM (EMQX default), and the sensors disappear from Home Assistant | Discovery is republished on every reconnection    |

The upstream scripts are not copied into this repository: they belong to Orb
Forge and have no license file. `update_scripts.sh` fetches them on your
machine.

## Requirements

- Docker with the Compose plugin.
- An MQTT broker reachable from the container (Mosquitto, EMQX…), with a user
  for Orb.
- The [MQTT integration](https://www.home-assistant.io/integrations/mqtt/) in
  Home Assistant, with discovery enabled (default prefix `homeassistant`).
- Internet access for the container: Orb measures your connection against its
  own servers.

## Installation

```sh
git clone https://github.com/francois-le-ko4la/ha-orb-container.git
cd ha-orb-container
./update_scripts.sh
cp docker-compose.example.yml docker-compose.yml
echo 'ORB_MQTT_PASS=your-password' > .env
# edit MQTT_HOST, MQTT_PORT, MQTT_USER in docker-compose.yml
docker compose up -d
docker compose logs -f orb-sensor
```

Then link the sensor to your account from the Orb app, as described in [Orb's
Docker guide](https://orb.net/docs/setup-sensor/docker).

To add it to an existing Compose stack, copy the `orb-sensor` service and adjust
the volume paths.

## Configuration

Use environment variables, or mount a copy of `options.example.json` as
`/data/options.json`. A variable takes precedence over the matching key.

| Variable             | `options.json` key | Default (file only) | Description                                                                      |
| -------------------- | ------------------ | ------------------- | -------------------------------------------------------------------------------- |
| `MQTT_PUSH`          | `mqtt_push`        | `false`             | `true` to publish to MQTT                                                        |
| `MQTT_HOST`          | `mqtt_host`        |                     | Broker host or IP                                                                |
| `MQTT_PORT`          | `mqtt_port`        | `1883`              | Broker port                                                                      |
| `MQTT_USER`          | `mqtt_user`        |                     | Broker user                                                                      |
| `MQTT_PASS`          | `mqtt_password`    |                     | Broker password                                                                  |
| `MQTT_PAUSE`         | `mqtt_frequency`   | `5`                 | Seconds between two publications                                                 |
| `DEBUG_MODE`         | `mqtt_debug`       | `false`             | `true` to log the MQTT settings                                                  |
| `ORB_EPHEMERAL_MODE` | `ephemeral_mode`   | `false`             | No disk writes (SD cards); stats are lost on restart. Variable: `1`, key: `true` |

Defaults only apply with the file. Without it, set every MQTT variable,
`MQTT_PAUSE` included. Using `MQTT_HOST` makes the script read `MQTT_PORT`,
`MQTT_USER` and `MQTT_PASS` from the environment only.

## Entities

One **Orb Sensor** device. The sensors are defined by the upstream `mqtt.sh` and
follow its changes; at the time of writing:

| Sensor               | Unit |
| -------------------- | ---- |
| Score                | %    |
| Bandwidth Score      | %    |
| Reliability Score    | %    |
| Responsiveness Score | %    |
| Bandwidth Upload     | kbps |
| Bandwidth Download   | kbps |
| Lag                  | µs   |

A sensor reports `unknown` while Orb has no value for it (for example before the
first speed test).

See the upstream
[`mqtt.sh`](https://github.com/orbforge/addon-orb/blob/main/docker/mqtt.sh)
(`mapping` block) for the current list.

## Updating

```sh
docker compose pull orb-sensor   # Orb sensor binary
./update_scripts.sh              # upstream scripts, re-patched
docker compose up -d orb-sensor
```

If an upstream change breaks a patch, `update_scripts.sh` stops, says which one,
and leaves your current scripts untouched.

## Troubleshooting

| Symptom                                             | Cause / fix                                                                                    |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `MQTT broker unreachable, retrying in 10s`          | Broker down or wrong `MQTT_HOST`/`MQTT_PORT`; the script keeps retrying                        |
| `Error: Missing MQTT configuration`                 | One of `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASS` is empty                             |
| `jq: error: Could not open file /data/options.json` | Harmless when you configure with environment variables                                         |
| No sensors in Home Assistant                        | Check that MQTT discovery is enabled and that the broker user can publish to `homeassistant/#` |
| `cap_net_admin capability not found`                | Harmless: nearby Wi-Fi access point measurement is not available in a container                |

## Credits

- [Orb Forge](https://orb.net) for the Orb sensor, the `orbforge/orb-ha` image
  and the [add-on scripts](https://github.com/orbforge/addon-orb).

## License

The files in this repository are under the [GPL-3.0](LICENSE). The upstream
scripts fetched by `update_scripts.sh` keep their own terms.
