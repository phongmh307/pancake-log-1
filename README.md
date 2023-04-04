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

Params(:pancake_log):
|       Name         | Required | Default |               Notes                       |
|       :---:        |  :---:   |  :---:  |               :---:                       |
| log_final_storage  |  true    |   n/a   | Must be list. Allow value(:s3, :logstash) |
| enable_sentry_mode |  false   |  false  | Sentry mode will log all info of app you config (follow params sentry_mode to get more information) |

Params(:pancake_log -> :sentry_mode) (Require if you use sentry mode)
|       Name         | Required | Default |               Notes                       |
|       :---:        |  :---:   |  :---:  |               :---:                       |
|       :level       |  false   |  :error | Level info you wanna log (ex: :debug, :warn, :error, ...)|
|       :metadata    |  false   |  :node  | Crash record will include this value (must be keyword list) (default we add node name for you)|
|   :logstash_index  |  true    |   n/a   |         Index name of logstash            |

Params(:pancake_log -> :s3) (Require if you use s3 storage)
|       Name         | Required | Default |               Notes                       |
|       :---:        |  :---:   |  :---:  |               :---:                       |
|    storage_path    |  true    |   n/a   | This is area to buffer your log before upload to s3 |
|    adapter_port    |  true    |   n/a   |  This is port our server collect log data |

Params(:pancake_log -> :logstash)
|        Name          | Required |     Default  |               Notes                       |
|        :---:         |  :---:   |     :---:    |               :---:                       |
| use_logcake_logstash |  false   |     true     | We have logstash adapter in lib (set to false if you wanna use your logstash) |
|         ip           |  false   | '10.1.8.196' |  Logstash IP (default is Logstash of Pancake)  |
|        port          |  false   |     5046     | Logstash Port (default is Logstash of Pancake) |
|     mf_logstash      |  false   |     n/a      | Require if you wanna use your logstash. It's module and function of your logstash |

Log to file using log/1 function:

```elixir
LogCake.log("hello world", a: 1, b: "2")
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pancake_log>.

