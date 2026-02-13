# ExRmtfs

Manages `udevd` and `rmtfs` daemons for Qualcomm's remoteproc subsystem on
[Nerves](https://nerves-project.org/) devices (e.g., the Fairphone 2).

The `rmtfs` daemon provides a remote filesystem service that gives the Qualcomm
modem co-processor access to shared memory regions for modem firmware and EFS
storage. This library handles the full startup sequence: launching `udevd`,
triggering device enumeration, waiting for settle, and then starting `rmtfs` --
all under an OTP supervisor.

## Architecture

```
ExRmtfs (Supervisor, :rest_for_one)
  |
  +-- ExRmtfs.Udevd (GenServer)
  |     |-- Starts udevd via MuonTrap.Daemon
  |     |-- Runs: udevadm trigger --type=subsystems --action=add
  |     |-- Runs: udevadm trigger --type=devices --action=add
  |     +-- Runs: udevadm settle --timeout=<settle_timeout>
  |
  +-- ExRmtfs.Daemon (GenServer)
        +-- Starts rmtfs via MuonTrap.Daemon
```

The `:rest_for_one` strategy ensures that if `udevd` crashes, the `rmtfs`
daemon is also restarted, since it depends on the device nodes being present.

## Installation

Add `ex_rmtfs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_rmtfs, github: "mlainez/ex_rmtfs"}
  ]
end
```

## Usage

The application starts automatically via its OTP application callback. If you
prefer manual control, add `ExRmtfs` to your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {ExRmtfs, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Options

Options are passed as a keyword list:

| Option | Type | Default | Description |
|---|---|---|---|
| `:udevd_args` | `String.t()` | `""` | Extra arguments for the `udevd` daemon |
| `:udevd_env` | `[{String.t(), String.t()}]` | `[]` | Environment variables for `udevd` |
| `:rmtfs_args` | `String.t()` | `"-P -r -s"` | Arguments for the `rmtfs` daemon |
| `:rmtfs_env` | `[{String.t(), String.t()}]` | `[]` | Environment variables for `rmtfs` |
| `:udevd_settle_timeout` | `pos_integer()` | `30` | Timeout in seconds for `udevadm settle` |

Example with custom options:

```elixir
{ExRmtfs, rmtfs_args: "-P -r", udevd_settle_timeout: 60}
```

## License

Apache-2.0
