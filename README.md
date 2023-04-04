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
  log_final_storage: [:logstash],
  enable_sentry_mode: true
```

```elixir
config :pancake_log, :sentry_mode,
  logstash_index: index_name (config tên index trên logstash tuỳ từng app)
```

Log to file using log/1 function:

```elixir
LogCake.log("hello world", a: 1, b: "2")
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pancake_log>.

