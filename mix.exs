defmodule Membrane.ERTMP.Mixfile do
  use Mix.Project

  @version "0.1.2"
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
      homepage_url: "https://membrane.stream",
      aliases: [docs: ["docs", &append_llms_links/1]]
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
      {:membrane_vp8_format, "~> 0.5"},
      {:membrane_vp9_format, "~> 0.5"},
      {:membrane_file_plugin, "~> 0.17", only: [:dev, :test]},
      {:membrane_h26x_plugin, "~> 0.10.0", only: [:dev, :test]},
      {:membrane_aac_plugin, "~> 0.19", only: [:dev, :test]},
      {:membrane_ogg_plugin, "~> 0.5.1", only: [:dev, :test]},
      {:membrane_opus_plugin, "~> 0.20.7", only: [:dev, :test]},
      {:membrane_ivf_plugin, "~> 0.9.0", only: [:dev, :test]},
      {:membrane_mp4_plugin, "~> 0.36.9", only: [:dev, :test]},
      {:membrane_realtimer_plugin, "~> 0.11", only: :dev},
      {:ex_doc, ">= 0.40.0", only: :dev, runtime: false},
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
      },
      files: [
        "lib",
        "native",
        "Cargo.toml",
        "Cargo.lock",
        "mix.exs",
        "README*",
        "LICENSE*",
        ".formatter.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.ERTMP]
    ]
  end

  defp append_llms_links(_args) do
    output_dir = docs()[:output] || "doc"
    path = Path.join(output_dir, "llms.txt")

    if File.exists?(path) do
      existing = File.read!(path)

      footer = """


      ## See Also

      - [Membrane Framework AI Skill](https://hexdocs.pm/membrane_core/skill.md)
      - [Membrane Core](https://hexdocs.pm/membrane_core/llms.txt)
      """

      File.write!(path, String.trim_trailing(existing) <> footer)
    else
      IO.warn("#{path} not found — llms.txt was not generated, check your ex_doc configuration")
    end
  end
end
