defmodule LogCake.Application do
  use Application
  import Supervisor.Spec, warn: false

  def start(_type, _args) do
    ensure_config_exists()

    storage_path = Application.get_env(:pancake_log, :storage_path)
    File.mkdir_p!(storage_path)

    endpoint_opts = [port: Application.get_env(:pancake_log, :adapter_port)]

    children = [
      {LogCake.Endpoint, endpoint_opts}
    ]

    opts = [strategy: :one_for_one, name: EventHubCake.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_config_exists do
    adapter_port = Application.get_env(:pancake_log, :adapter_port)
    storage_path = Application.get_env(:pancake_log, :storage_path)

    if !adapter_port,
      do:
        raise(ArgumentError,
          message: "Missing adapter_port in :pancake_log application config"
        )

    if !storage_path,
      do:
        raise(ArgumentError,
          message: "Missing storage_path in :pancake_log application config"
        )
  end
end
