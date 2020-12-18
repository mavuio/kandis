defmodule Kandis.MixProject do
  use Mix.Project

  # use "bump_ex messagel" - command instead
  @version "0.3.25"
  def project do
    [
      app: :kandis,
      version: @version,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Kandis.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:myxql, "~> 0.3.0", only: :test},
      {:accessible, "~> 0.2.1"},
      {:bertex, "~> 1.3"},
      {:struct_access, "~> 1.1.2"},
      {:elixir_xml_to_map, "~> 0.2"},
      {:stripy, "~> 2.0"},
      {:atomic_map, "~> 0.8"},
      {:blankable, "~> 1.0"},
      # {:phoenix, "~> 1.4.0", only: :test},
      {:phoenix_live_view, "~> 0.15"},
      {:phoenix_html, "~> 2.11"},
      {:pow, "~> 1.0.18", only: :test},
      {:httpoison, "~> 0.13 or ~> 1.0"},
      {:download, "~> 0.0.4"}

      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
