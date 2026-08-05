defmodule Episteme.MixProject do
  use Mix.Project

  @version "0.2.0"

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
      {:ichor_runtime, "~> 0.2"}
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
        "sobelow --skip",
        "test",
        "dialyzer"
      ]
    ]
  end

  defp description do
    "A standalone Prolog-like resolution engine and clause database for Elixir: " <>
      "terms, unification, SLD-resolution, backtracking, a genuine clause-scoped cut, " <>
      "and builtin predicates, built on Ichor's search substrate. No parser -- bring " <>
      "your own front-end (e.g. Aletheia) or build goal terms directly."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/joetjen/episteme",
        "Docs" => "https://joetjen.github.io/episteme"
      },
      files: ~w(lib .formatter.exs mix.exs README.md TUTORIAL.md REFERENCE.md EXAMPLES.md
           CASE_STUDY.md CHEATSHEET.md CHANGELOG.md CONTRIBUTING.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/joetjen/episteme",
      source_ref: "v#{@version}",
      homepage_url: "https://joetjen.github.io/episteme",
      extras: extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  # Doc navigation order: README first (it's `main`), then the
  # learn-the-library docs -- narrative walkthrough, full feature-by-
  # feature reference, then worked programs (many small ones, then one
  # large one) -- then the quick lookup doc, then project-process docs
  # last.
  defp extras do
    [
      "README.md",
      "TUTORIAL.md",
      "REFERENCE.md",
      "EXAMPLES.md",
      "CASE_STUDY.md",
      "CHEATSHEET.md",
      "CHANGELOG.md",
      "CONTRIBUTING.md",
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
      "Database Backends": [
        Episteme.Database.Backend,
        Episteme.Database.Backends.Ets,
        Episteme.Database.Backends.Dets
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
