defmodule Rmtfs.Daemon do
  @moduledoc """
  Manages the `rmtfs` daemon process.

  The `rmtfs` daemon provides a remote filesystem service used by Qualcomm's
  remoteproc subsystem. It is responsible for providing access to shared memory
  regions (e.g., modem firmware storage) needed by the modem processor.

  This GenServer starts `rmtfs` via `MuonTrap.Daemon` and monitors it.

  ## Options

  * `:rmtfs_args` - arguments for the `rmtfs` command (default: `"-P -r -s"`)
  * `:rmtfs_env` - environment variables as `{"KEY", "VALUE"}` tuples (default: `[]`)
  """

  use GenServer

  require Logger

  @default_args "-P -r -s"
  @default_env []

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    args = Keyword.get(opts, :rmtfs_args, @default_args)
    env = Keyword.get(opts, :rmtfs_env, @default_env)

    Logger.info("[Rmtfs.Daemon] Starting rmtfs with args: #{args}")

    {:ok, pid} =
      MuonTrap.Daemon.start_link("rmtfs", String.split(args),
        env: env,
        stderr_to_stdout: true,
        log_output: :debug,
        log_prefix: "rmtfs: "
      )

    Logger.info("[Rmtfs.Daemon] rmtfs started")

    {:ok, %{daemon_pid: pid}}
  end
end
