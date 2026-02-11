defmodule ExRmtfs.Udevd do
  @moduledoc """
  Manages the `udevd` daemon and triggers device enumeration.

  This GenServer starts `udevd` via `MuonTrap.Daemon`, then runs `udevadm`
  commands to trigger subsystem and device enumeration and waits for the
  settle phase to complete. This ensures all devices (including the QMI
  modem device nodes) are available before `rmtfs` starts.

  ## Options

  * `:udevd_args` - extra arguments for the `udevd` command (default: `""`)
  * `:udevd_env` - environment variables as `{"KEY", "VALUE"}` tuples (default: `[]`)
  * `:udevd_settle_timeout` - timeout in seconds for `udevadm settle` (default: `30`)
  """

  use GenServer

  require Logger

  @default_args ""
  @default_env []
  @default_settle_timeout 30

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run a `udevadm` command.

  Returns `{output, exit_status}`.
  """
  @spec udevadm(String.t()) :: {Collectable.t(), exit_status :: non_neg_integer()}
  def udevadm(args) do
    System.shell("udevadm #{args}", stderr_to_stdout: true, into: IO.stream(:stdio, :line))
  end

  @impl GenServer
  def init(opts) do
    args = Keyword.get(opts, :udevd_args, @default_args)
    env = Keyword.get(opts, :udevd_env, @default_env)
    settle_timeout = Keyword.get(opts, :udevd_settle_timeout, @default_settle_timeout)

    Logger.info("[ExRmtfs.Udevd] Starting udevd")

    {:ok, pid} =
      MuonTrap.Daemon.start_link("udevd", String.split(args),
        env: env,
        stderr_to_stdout: true,
        log_output: :debug,
        log_prefix: "udevd: "
      )

    Logger.info("[ExRmtfs.Udevd] Triggering device enumeration")

    {_, 0} = udevadm("trigger --type=subsystems --action=add")
    {_, 0} = udevadm("trigger --type=devices --action=add")
    {_, 0} = udevadm("settle --timeout=#{settle_timeout}")

    Logger.info("[ExRmtfs.Udevd] Device enumeration complete")

    {:ok, %{daemon_pid: pid}}
  end
end
