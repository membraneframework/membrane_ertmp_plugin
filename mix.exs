defmodule Membrane.ERTMP.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework/membrane_ertmp_plugin"

  def project do
    [
      app: :membrane_ertmp_plugin,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # hex
      description:
        "Membrane plugin for Enhanced RTMP (ERTMP) output via software-mansion/smelter",
      package: package(),

      # docs
      name: "Membrane ERTMP Plugin",
      source_url: @github_url,
      docs: docs(),
      homepage_url: "https://membrane.stream"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 1.0"},
      {:rustler, "~> 0.34"},
      {:membrane_h264_format, "~> 0.6"},
      {:membrane_aac_format, "~> 0.8"},
      {:membrane_opus_format, "~> 0.3"},
      {:membrane_file_plugin, "~> 0.17", only: [:dev, :test]},
      {:membrane_h26x_plugin, "~> 0.10", only: [:dev, :test]},
      {:membrane_aac_plugin, "~> 0.19", only: [:dev, :test]},
      {:membrane_realtimer_plugin, "~> 0.11", only: :dev},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    opts = [flags: [:error_handling]]

    if System.get_env("CI") == "true" do
      File.mkdir_p!(Path.join([__DIR__, "priv", "plts"]))
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp package do
    [
      maintainers: ["Software Mansion"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.ERTMP]
    ]
  end
end
