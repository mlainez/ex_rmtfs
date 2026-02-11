defmodule ExRmtfs do
  @moduledoc """
  Manages udevd and rmtfs daemons for Qualcomm remoteproc on Nerves devices.

  This library starts `udevd` (triggering device enumeration) followed by the
  `rmtfs` daemon, which provides the remote filesystem service required by
  Qualcomm's remoteproc subsystem (e.g., on the Fairphone 2).

  ## Usage

  Add `ExRmtfs` to your application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {ExRmtfs, []}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  ## Options

  Options are passed as a keyword list:

  * `:udevd_args` - extra arguments for the `udevd` daemon (default: `""`)
  * `:udevd_env` - environment variables for `udevd` as a list of `{"KEY", "VALUE"}` tuples (default: `[]`)
  * `:rmtfs_args` - arguments for the `rmtfs` daemon (default: `"-P -r -s"`)
  * `:rmtfs_env` - environment variables for `rmtfs` as a list of `{"KEY", "VALUE"}` tuples (default: `[]`)
  * `:udevd_settle_timeout` - timeout in seconds for `udevadm settle` (default: `30`)

  ## Example with custom options

      {ExRmtfs, rmtfs_args: "-P -r", udevd_settle_timeout: 60}
  """

  use Supervisor

  @type option ::
          {:udevd_args, String.t()}
          | {:udevd_env, [{String.t(), String.t()}]}
          | {:rmtfs_args, String.t()}
          | {:rmtfs_env, [{String.t(), String.t()}]}
          | {:udevd_settle_timeout, pos_integer()}

  @doc """
  Starts the ExRmtfs supervisor.

  See the module documentation for available options.
  """
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    children = [
      {ExRmtfs.Udevd, opts},
      {ExRmtfs.Daemon, opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
