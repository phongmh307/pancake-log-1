# LogCake

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pancake_log` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pancake_log, "~> 0.1.0"}
  ]
end
```

Then add your configuration:

```elixir
config :pancake_log,
  adapter_port: 4002,
  storage_path: "./test_log"
```

Log to file using log/1 function:

```elixir
LogCake.log("hello world", a: 1, b: "2")
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pancake_log>.

