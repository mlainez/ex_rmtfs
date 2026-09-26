# ExRmtfs

> ### ⚠️ Very early work — built for a workshop, not for production
>
> Written for the **Goatmire Elixir workshop** on running Nerves on Fairphone 3 hardware. There are no stability guarantees and APIs will change without notice.

Runs `udevd` and Qualcomm's [`rmtfs`](https://github.com/linux-msm/rmtfs)
daemon on [Nerves](https://nerves-project.org/) devices (built for the
Fairphone 3).

`rmtfs` serves the modem's EFS partitions (`modemst1`, `modemst2`, `fsg`,
`fsc`) over QRTR. With the default `-P` flag it finds those partitions via
`/dev/disk/by-partlabel/`, and on the Fairphone 3 kernel QRTR and the modem
remoteproc driver are modules that udev autoloads. So this library starts
`udevd`, triggers device enumeration, waits for `udevadm settle`, and only
then starts `rmtfs`.

## Requirements

On the target (all provided by `nerves_system_fp3`):

- `udevd` and `udevadm` (Buildroot `eudev`, selected via
  `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV`)
- `rmtfs` (`packages/rmtfs`, installs `/usr/bin/rmtfs` and its udev rules)
- a kernel with QRTR and the Qualcomm remoteproc drivers

## Installation

```elixir
def deps do
  [
    {:ex_rmtfs, github: "mlainez/ex_rmtfs"}
  ]
end
```

## Usage

The `:ex_rmtfs` application starts everything automatically, using options
from the application environment. Nothing else is needed:

```elixir
# config/target.exs (all keys optional; defaults shown)
config :ex_rmtfs,
  rmtfs_args: "-P -r -s",
  udevd_settle_timeout: 30
```

To supervise it yourself instead, turn the automatic start off and add
`{ExRmtfs, opts}` to your own tree. Only one instance can run at a time
(the processes have fixed names).

```elixir
config :ex_rmtfs, start: false
```

```elixir
children = [
  {ExRmtfs, rmtfs_args: "-P -r -s"}
]
```

### Options

The same keys work in `config :ex_rmtfs` and as `{ExRmtfs, opts}`.

| Key | Default | Description |
|---|---|---|
| `:start` | `true` | App env only. `false` disables the automatic start |
| `:udevd_path` | `"udevd"` | udevd executable (looked up on `$PATH`) |
| `:udevd_args` | `""` | Extra udevd arguments (string or list) |
| `:udevd_env` | `[]` | udevd environment, `[{"KEY", "VALUE"}]` |
| `:udevadm_path` | `"udevadm"` | udevadm executable |
| `:udev_control_path` | `"/run/udev/control"` | Socket whose appearance means udevd is listening |
| `:udevd_ready_timeout` | `10_000` | ms to wait for that socket before triggering anyway |
| `:udevd_settle_timeout` | `30` | Seconds passed to `udevadm settle --timeout` |
| `:rmtfs_path` | `"rmtfs"` | rmtfs executable |
| `:rmtfs_args` | `"-P -r -s"` | rmtfs arguments (string or list) |
| `:rmtfs_env` | `[]` | rmtfs environment, `[{"KEY", "VALUE"}]` |
| `:min_backoff_ms` | `1_000` | First restart delay for a missing or exited daemon |
| `:max_backoff_ms` | `60_000` | Maximum restart delay |

rmtfs flags (from the rmtfs source): `-P` use raw EFS partitions, `-r`
read-only (never write to storage), `-s` sync with the modem remoteproc
(start/stop it along with rmtfs), `-v` verbose, `-o DIR` storage root.

## Process tree

```
ExRmtfs (Supervisor, :rest_for_one)
  ExRmtfs.Udevd.Daemon   udevd under MuonTrap
  ExRmtfs.Udevd          waits for /run/udev/control, then
                         udevadm trigger --type=subsystems --action=add
                         udevadm trigger --type=devices --action=add
                         udevadm settle --timeout=<udevd_settle_timeout>
  ExRmtfs.Rmtfs.Daemon   rmtfs under MuonTrap, started once ExRmtfs.Udevd
                         has finished
```

Boot safety: a missing executable, a failing `udevadm` or a daemon that
exits (with any status) is logged and retried with exponential backoff.
None of these make the supervisor or the application exit, so they cannot
reboot a device running with `start_permanent`. `udevadm` output goes to
Logger at `:debug`, `udevd` output at `:debug` and `rmtfs` output at `:info`.

Enumeration runs once when `ExRmtfs.Udevd` starts; it is not repeated when
`udevd` is restarted.

## Status

The code is tested on the host with fake executables. Behaviour on the
Fairphone 3 has not been re-verified since the restart/backoff and
configuration changes.

## Toolchain

Built and tested with Erlang/OTP 29.1.1 and Elixir 1.20.4, matching the official Nerves systems (see `.tool-versions`).

## License

MIT, see [LICENSE](LICENSE).
