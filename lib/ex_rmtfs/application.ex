defmodule ExRmtfs.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    ExRmtfs.start_link([])
  end
end
