defmodule ExRmtfsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  defp script(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp eventually(fun, timeout \\ 5_000) do
    cond do
      fun.() ->
        true

      timeout <= 0 ->
        flunk("condition not met in time")

      true ->
        Process.sleep(50)
        eventually(fun, timeout - 50)
    end
  end

  defp log_lines(log) do
    case File.read(log) do
      {:ok, content} -> String.split(content, "\n", trim: true)
      _ -> []
    end
  end

  defp base_opts(dir) do
    [
      udev_control_path: Path.join(dir, "udev/control"),
      udevd_ready_timeout: 2_000,
      udevd_settle_timeout: 5,
      min_backoff_ms: 50,
      max_backoff_ms: 200
    ]
  end

  test "child_spec is a supervisor spec that carries the options" do
    opts = [rmtfs_args: "-P -r", udevd_settle_timeout: 60]

    assert %{id: ExRmtfs, start: {ExRmtfs, :start_link, [^opts]}, type: :supervisor} =
             ExRmtfs.child_spec(opts)
  end

  test "starts udevd, waits for it, triggers, settles, then starts rmtfs", %{tmp_dir: dir} do
    log = Path.join(dir, "log")
    control = Path.join(dir, "udev/control")

    udevd =
      script(dir, "udevd", """
      sleep 0.3
      mkdir -p #{Path.dirname(control)}
      touch #{control}
      echo "udevd $*" >> #{log}
      exec sleep 1000
      """)

    udevadm = script(dir, "udevadm", ~s(echo "udevadm $*" >> #{log}\n))
    rmtfs = script(dir, "rmtfs", ~s(echo "rmtfs $*" >> #{log}\nexec sleep 1000\n))

    start_supervised!(
      {ExRmtfs, base_opts(dir) ++ [udevd_path: udevd, udevadm_path: udevadm, rmtfs_path: rmtfs]}
    )

    eventually(fn -> length(log_lines(log)) == 5 end)

    assert log_lines(log) == [
             "udevd ",
             "udevadm trigger --type=subsystems --action=add",
             "udevadm trigger --type=devices --action=add",
             "udevadm settle --timeout=5",
             "rmtfs -P -r -s"
           ]

    assert ExRmtfs.Udevd.settled?()
    assert %{status: :running, starts: 1} = ExRmtfs.Daemon.status(ExRmtfs.Rmtfs.Daemon)
  end

  test "rmtfs_args accepts a list", %{tmp_dir: dir} do
    log = Path.join(dir, "log")
    udevadm = script(dir, "udevadm", "exit 0\n")
    rmtfs = script(dir, "rmtfs", ~s(echo "$*" >> #{log}\nexec sleep 1000\n))

    start_supervised!(
      {ExRmtfs,
       base_opts(dir) ++
         [
           udevd_path: Path.join(dir, "missing-udevd"),
           udevd_ready_timeout: 0,
           udevadm_path: udevadm,
           rmtfs_path: rmtfs,
           rmtfs_args: ["-P", "-v"]
         ]}
    )

    eventually(fn -> log_lines(log) == ["-P -v"] end)
  end

  test "missing binaries are logged and retried, never crash the supervisor", %{tmp_dir: dir} do
    missing = &Path.join(dir, "missing-" <> &1)

    pid =
      start_supervised!(
        {ExRmtfs,
         base_opts(dir) ++
           [
             udevd_path: missing.("udevd"),
             udevadm_path: missing.("udevadm"),
             rmtfs_path: missing.("rmtfs"),
             udevd_ready_timeout: 200
           ]}
      )

    eventually(fn -> ExRmtfs.Udevd.settled?() end)
    eventually(fn -> ExRmtfs.Daemon.status(ExRmtfs.Rmtfs.Daemon).status == :backoff end)
    assert %{starts: 0} = ExRmtfs.Daemon.status(ExRmtfs.Udevd.Daemon)
    Process.sleep(500)
    assert Process.alive?(pid)
    assert [_, _, _] = Supervisor.which_children(pid)
  end

  test "failing udevadm is tolerated and rmtfs still starts", %{tmp_dir: dir} do
    log = Path.join(dir, "log")
    udevadm = script(dir, "udevadm", "echo boom\nexit 1\n")
    rmtfs = script(dir, "rmtfs", ~s(echo "rmtfs" >> #{log}\nexec sleep 1000\n))

    start_supervised!(
      {ExRmtfs,
       base_opts(dir) ++
         [
           udevd_path: Path.join(dir, "missing-udevd"),
           udevd_ready_timeout: 0,
           udevadm_path: udevadm,
           rmtfs_path: rmtfs
         ]}
    )

    eventually(fn -> log_lines(log) == ["rmtfs"] end)
  end

  describe "ExRmtfs.Udevd.udevadm/2" do
    test "returns output, exit status errors and :enoent", %{tmp_dir: dir} do
      ok = script(dir, "ok", "echo hello\n")
      bad = script(dir, "bad", "echo nope >&2\nexit 3\n")

      assert {:ok, "hello\n"} = ExRmtfs.Udevd.udevadm([], ok)
      assert {:error, {3, "nope"}} = ExRmtfs.Udevd.udevadm([], bad)
      assert {:error, :enoent} = ExRmtfs.Udevd.udevadm([], Path.join(dir, "missing"))
    end
  end

  describe "ExRmtfs.Daemon" do
    test "restarts a daemon that exits, even with status 0", %{tmp_dir: dir} do
      exits = script(dir, "exits", "exit 0\n")

      pid =
        start_supervised!(
          {ExRmtfs.Daemon, command: exits, min_backoff_ms: 20, max_backoff_ms: 40}
        )

      eventually(fn -> ExRmtfs.Daemon.status(pid).starts >= 3 end)
      assert Process.alive?(pid)
    end

    test "waits for :wait_for before starting", %{tmp_dir: dir} do
      flag = Path.join(dir, "flag")
      sleeper = script(dir, "sleeper", "exec sleep 1000\n")

      pid =
        start_supervised!(
          {ExRmtfs.Daemon, command: sleeper, poll_ms: 20, wait_for: fn -> File.exists?(flag) end}
        )

      Process.sleep(100)
      assert %{status: :waiting, starts: 0} = ExRmtfs.Daemon.status(pid)

      File.touch!(flag)
      eventually(fn -> ExRmtfs.Daemon.status(pid).status == :running end)
    end

    test "stops the OS process when the runner stops", %{tmp_dir: dir} do
      pidfile = Path.join(dir, "pid")
      sleeper = script(dir, "sleeper", "echo $$ > #{pidfile}\nexec sleep 1000\n")

      start_supervised!({ExRmtfs.Daemon, command: sleeper})
      eventually(fn -> File.exists?(pidfile) end)
      os_pid = pidfile |> File.read!() |> String.trim()

      stop_supervised!(ExRmtfs.Daemon)
      eventually(fn -> not File.exists?("/proc/#{os_pid}") end)
    end
  end

  describe "ExRmtfs.Application" do
    test "does not start ExRmtfs when start: false" do
      assert Application.get_env(:ex_rmtfs, :start) == false
      assert Supervisor.which_children(ExRmtfs.Application) == []
    end
  end
end
