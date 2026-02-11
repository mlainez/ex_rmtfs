defmodule RmtfsTest do
  use ExUnit.Case, async: true

  test "default options are applied" do
    # Verify the supervisor child spec is correct
    child_spec = Rmtfs.child_spec([])

    assert child_spec == %{
             id: Rmtfs,
             start: {Rmtfs, :start_link, [[]]},
             type: :supervisor
           }
  end

  test "custom options are passed through" do
    opts = [rmtfs_args: "-P -r", udevd_settle_timeout: 60]
    child_spec = Rmtfs.child_spec(opts)

    assert child_spec == %{
             id: Rmtfs,
             start: {Rmtfs, :start_link, [opts]},
             type: :supervisor
           }
  end
end
