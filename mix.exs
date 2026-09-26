defmodule ExRmtfs.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mlainez/ex_rmtfs"

  def project do
    [
      app: :ex_rmtfs,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      dialyzer: dialyzer(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      mod: {ExRmtfs.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:muontrap, "~> 1.0"},
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Runs udevd and the Qualcomm rmtfs daemon (modem EFS over QRTR) on Nerves devices"
  end

  defp dialyzer do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs]
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
