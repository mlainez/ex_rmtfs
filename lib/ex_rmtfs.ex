defmodule ExRmtfs do
  @moduledoc """
  Runs `udevd` and the Qualcomm `rmtfs` daemon on Nerves devices (built for
  the Fairphone 3).

  `rmtfs` serves the modem's EFS (the `modemst1`, `modemst2`, `fsg` and
  `fsc` partitions) over QRTR. With the default `-P` flag it opens those
  partitions via `/dev/disk/by-partlabel/`, which is why `udevd` is started
  and device enumeration triggered first.

  ## Start model

  The `:ex_rmtfs` application starts this supervisor automatically, with
  options read from the application environment:

      config :ex_rmtfs,
        rmtfs_args: "-P -r -s",
        udevd_settle_timeout: 30

  To supervise it yourself instead, disable the automatic start and add
  `{ExRmtfs, opts}` to your own tree (only one instance can run, since the
  processes use fixed names):

      config :ex_rmtfs, start: false

      children = [{ExRmtfs, rmtfs_args: "-P -r -s"}]

  ## Process tree

      ExRmtfs (Supervisor, :rest_for_one)
        ExRmtfs.Udevd.Daemon  - udevd under MuonTrap (ExRmtfs.Daemon)
        ExRmtfs.Udevd         - udevadm trigger + settle
        ExRmtfs.Rmtfs.Daemon  - rmtfs under MuonTrap (ExRmtfs.Daemon),
                                started once ExRmtfs.Udevd has settled

  A missing binary or a daemon that exits is logged and retried with
  exponential backoff (see `ExRmtfs.Daemon`); it never makes the
  supervisor or the application exit.

  ## Options

    * `:udevd_path` - udevd executable (default `"udevd"`)
    * `:udevd_args` - extra udevd arguments, string or list (default `""`)
    * `:udevd_env` - udevd environment as `{"KEY", "VALUE"}` tuples (default `[]`)
    * `:udevadm_path` - udevadm executable (default `"udevadm"`)
    * `:udev_control_path` - socket that signals udevd is ready (default `"/run/udev/control"`)
    * `:udevd_ready_timeout` - ms to wait for that socket (default `10_000`)
    * `:udevd_settle_timeout` - seconds for `udevadm settle` (default `30`)
    * `:rmtfs_path` - rmtfs executable (default `"rmtfs"`)
    * `:rmtfs_args` - rmtfs arguments, string or list (default `"-P -r -s"`)
    * `:rmtfs_env` - rmtfs environment as `{"KEY", "VALUE"}` tuples (default `[]`)
    * `:min_backoff_ms` / `:max_backoff_ms` - daemon restart backoff
      (default `1_000` / `60_000`)

  Executables given without a `/` are looked up on `$PATH`.
  """

  use Supervisor

  @type option ::
          {:udevd_path, String.t()}
          | {:udevd_args, String.t() | [String.t()]}
          | {:udevd_env, [{String.t(), String.t()}]}
          | {:udevadm_path, String.t()}
          | {:udev_control_path, Path.t()}
          | {:udevd_ready_timeout, non_neg_integer()}
          | {:udevd_settle_timeout, pos_integer()}
          | {:rmtfs_path, String.t()}
          | {:rmtfs_args, String.t() | [String.t()]}
          | {:rmtfs_env, [{String.t(), String.t()}]}
          | {:min_backoff_ms, pos_integer()}
          | {:max_backoff_ms, pos_integer()}

  @doc """
  Starts the ExRmtfs supervisor, registered as `ExRmtfs`.

  See the module documentation for available options.
  """
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    backoff = Keyword.take(opts, [:min_backoff_ms, :max_backoff_ms])

    udevd =
      [
        id: ExRmtfs.Udevd.Daemon,
        name: ExRmtfs.Udevd.Daemon,
        command: Keyword.get(opts, :udevd_path, "udevd"),
        args: Keyword.get(opts, :udevd_args, ""),
        env: Keyword.get(opts, :udevd_env, []),
        log_output: :debug,
        log_prefix: "udevd: "
      ] ++ backoff

    rmtfs =
      [
        id: ExRmtfs.Rmtfs.Daemon,
        name: ExRmtfs.Rmtfs.Daemon,
        command: Keyword.get(opts, :rmtfs_path, "rmtfs"),
        args: Keyword.get(opts, :rmtfs_args, "-P -r -s"),
        env: Keyword.get(opts, :rmtfs_env, []),
        log_output: :info,
        log_prefix: "rmtfs: ",
        wait_for: &ExRmtfs.Udevd.settled?/0
      ] ++ backoff

    children = [
      {ExRmtfs.Daemon, udevd},
      {ExRmtfs.Udevd, opts},
      {ExRmtfs.Daemon, rmtfs}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
