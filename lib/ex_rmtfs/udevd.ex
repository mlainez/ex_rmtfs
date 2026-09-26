defmodule ExRmtfs.Udevd do
  @moduledoc """
  Triggers udev device enumeration once `udevd` is listening.

  `udevd` itself runs in a sibling `ExRmtfs.Daemon` process. This GenServer
  returns from `init/1` immediately and, in `handle_continue/2`:

    1. waits for udevd's control socket (`:udev_control_path`, default
       `/run/udev/control`) to appear, for at most `:udevd_ready_timeout` ms
       (it carries on with a warning after that);
    2. runs `udevadm trigger --type=subsystems --action=add`;
    3. runs `udevadm trigger --type=devices --action=add`;
    4. runs `udevadm settle --timeout=<udevd_settle_timeout>`.

  `udevadm` output is sent to Logger at `:debug`. A missing `udevadm` or a
  non-zero exit status (e.g. settle timing out) is logged as a warning and
  never crashes this process. Once the sequence has finished (successfully
  or not) `settled?/0` returns `true`, which is what `rmtfs` waits for.

  Enumeration runs once per start of this process; it is not repeated if
  `udevd` restarts.

  ## Options

    * `:udevadm_path` - `udevadm` executable (default `"udevadm"`, looked up on `$PATH`)
    * `:udev_control_path` - udevd control socket to wait for (default `"/run/udev/control"`)
    * `:udevd_ready_timeout` - ms to wait for the control socket (default `10_000`)
    * `:udevd_settle_timeout` - seconds passed to `udevadm settle` (default `30`)
  """

  use GenServer

  require Logger

  @default_udevadm "udevadm"
  @default_control "/run/udev/control"
  @default_ready_timeout 10_000
  @default_settle_timeout 30
  @poll_ms 100

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `true` once the trigger/settle sequence has finished.

  Returns `false` while it is still running or if this process is not alive.
  """
  @spec settled?() :: boolean()
  def settled? do
    GenServer.call(__MODULE__, :settled?, 1_000)
  catch
    :exit, _ -> false
  end

  @doc """
  Runs `udevadm` with `args`, logging its output at `:debug`.

  Returns `{:ok, output}` on exit status 0, `{:error, {status, output}}` on a
  non-zero exit status, or `{:error, :enoent}` when the executable is missing.
  """
  @spec udevadm([String.t()], String.t()) ::
          {:ok, String.t()} | {:error, :enoent | {non_neg_integer(), String.t()}}
  def udevadm(args, udevadm \\ @default_udevadm) do
    case System.find_executable(udevadm) do
      nil ->
        {:error, :enoent}

      path ->
        {output, status} = System.cmd(path, args, stderr_to_stdout: true)

        output
        |> String.split("\n", trim: true)
        |> Enum.each(&Logger.debug("udevadm: " <> &1))

        if status == 0, do: {:ok, output}, else: {:error, {status, String.trim(output)}}
    end
  end

  @impl GenServer
  def init(opts) do
    state = %{
      udevadm: Keyword.get(opts, :udevadm_path, @default_udevadm),
      control: Keyword.get(opts, :udev_control_path, @default_control),
      ready_timeout: Keyword.get(opts, :udevd_ready_timeout, @default_ready_timeout),
      settle_timeout: Keyword.get(opts, :udevd_settle_timeout, @default_settle_timeout),
      settled?: false
    }

    {:ok, state, {:continue, :enumerate}}
  end

  @impl GenServer
  def handle_continue(:enumerate, state) do
    if wait_for_file(state.control, state.ready_timeout) == :timeout do
      Logger.warning(
        "[ExRmtfs.Udevd] #{state.control} did not appear within #{state.ready_timeout} ms; triggering anyway"
      )
    end

    Logger.info("[ExRmtfs.Udevd] Triggering device enumeration")

    run(state, ["trigger", "--type=subsystems", "--action=add"])
    run(state, ["trigger", "--type=devices", "--action=add"])
    run(state, ["settle", "--timeout=#{state.settle_timeout}"])

    Logger.info("[ExRmtfs.Udevd] Device enumeration finished")
    {:noreply, %{state | settled?: true}}
  end

  @impl GenServer
  def handle_call(:settled?, _from, state), do: {:reply, state.settled?, state}

  defp run(state, args) do
    case udevadm(args, state.udevadm) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[ExRmtfs.Udevd] udevadm #{Enum.join(args, " ")} failed: #{inspect(reason)}"
        )
    end
  end

  defp wait_for_file(path, remaining) do
    cond do
      File.exists?(path) ->
        :ok

      remaining <= 0 ->
        :timeout

      true ->
        Process.sleep(@poll_ms)
        wait_for_file(path, remaining - @poll_ms)
    end
  end
end
