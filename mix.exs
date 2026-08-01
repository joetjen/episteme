defmodule Episteme.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :episteme,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:mix]],
      description: description(),
      package: package(),
      name: "Episteme",
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # === CODE QUALITY & STATIC ANALYSIS ===
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},

      # === TESTING ===
      {:stream_data, "~> 1.4", only: [:test]},

      # === DEVELOPMENT TOOLING ===
      {:ex_doc, "~> 0.40", only: [:dev], runtime: false},

      # === RUNTIME ===
      # The one real runtime dependency: Ichor.Backtrack (unification,
      # backtracking search) plus Ichor.Toolkit.TermWalk. Unlike Aletheia
      # (which also needs `ichor` itself, dev-only, for `mix ichor.gen`),
      # Episteme has no reader/grammar of its own, so `ichor` never
      # appears here at all.
      {:ichor_runtime, "~> 0.1.0"}
    ]
  end

  # Fast/cheap checks first so a broken commit fails quickly; dialyzer
  # (slowest, especially its first PLT build) runs last.
  defp aliases do
    [
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "sobelow",
        "test",
        "dialyzer"
      ]
    ]
  end

  defp description do
    "A standalone Prolog-like resolution engine and clause database for Elixir -- " <>
      "terms, unification, SLD-resolution, backtracking, a genuine clause-scoped cut, " <>
      "and a small builtin-predicate set, built directly on Ichor's search substrate. " <>
      "No parser and no dependency on any concrete surface syntax -- build the database " <>
      "and goal terms yourself, or use a front-end (Aletheia's reader is one) on top."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/joetjen/episteme"},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/joetjen/episteme",
      source_ref: "v#{@version}",
      extras: extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md",
      "LICENSE"
    ]
  end

  defp groups_for_modules do
    [
      "Top-level API": [
        Episteme
      ],
      "Term & Database": [
        Episteme.Term,
        Episteme.Term.Var,
        Episteme.Term.Compound,
        Episteme.Database
      ],
      Engine: [
        Episteme.Engine
      ],
      Builtins: [
        Episteme.Builtins.Arithmetic,
        Episteme.Builtins.Exceptions,
        Episteme.Builtins.Io,
        Episteme.Builtins.Lists
      ]
    ]
  end
end
