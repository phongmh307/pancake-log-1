defmodule LogCake.Endpoint do
  use Plug.Router

  plug(Plug.Parsers, parsers: [:urlencoded])
  plug(:match)
  plug(:dispatch)

  get "/:file_id" do
    %{"file_id" => file_id} = conn.params
    storage_path = Application.get_env(:pancake_log, :storage_path, "./test_log")

    with(
      {_, [_start_ts, _end_ts]} <- {:file_id_check, String.split(file_id, "_")},
      path = Path.join(storage_path, file_id),
      {_, true} <- {:file_check, File.exists?(path)}
    ) do
      send_file(conn, 200, path)
    else
      {:file_id_check, _} ->
        send_resp(
          conn,
          400,
          "Malformed file_id, the format must be <start_timestamp>_<end_timestamp>"
        )

      {:file_check, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  def child_spec(init_args) do
    %{
      id: __MODULE__,
      start: {Plug.Cowboy, :http, [__MODULE__, [], [port: init_args[:port]]]}
    }
  end
end
