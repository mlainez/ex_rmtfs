defmodule ExRmtfs.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    env = Application.get_all_env(:ex_rmtfs)

    children =
      if Keyword.get(env, :start, true) do
        [{ExRmtfs, Keyword.delete(env, :start)}]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: ExRmtfs.Application)
  end
end
