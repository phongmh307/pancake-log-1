defmodule LogCake.Logstash do
  def start_link() do
    pool_opts = [
      name: {:local, :logstash_pool},
      worker_module: __MODULE__.Connection,
      max_overflow: 2,
      size: 5
    ]
    children = [
      :poolboy.child_spec(:logstash_pool, pool_opts, [])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  # Có thể gửi 1 list payload để bulk log
  def log(payload) do
    spawn(fn -> send_log(payload) end)
    :ok
  end

  defp send_log(payload) do
    case preprocess_payload(payload) do
      {:ok, processed_payload} ->
        :poolboy.transaction(
          :logstash_pool,
          fn pid -> GenServer.cast(pid, {:send_log, processed_payload}) end
        )

      {:error, _} -> :fail_to_process
    end
  end

  defp preprocess_payload(payload) when is_list(payload) do
    agg_payload =
      payload
      |> Stream.map(fn single_payload ->
        case preprocess_payload(single_payload) do
          {:ok, processed_payload} -> processed_payload
          {:error, _} -> nil
        end
      end)
      |> Stream.reject(&is_nil/1)
      |> Enum.join()

    if agg_payload != "", do: {:ok, agg_payload}, else: {:error, :no_valid_entry}
  end

  defp preprocess_payload(payload) do
    payload
    |> ensure_key_exist()
    |> Enum.map(fn {field, content} ->
      content = handle_field_content(content)
      {field, content}
    end)
    |> Enum.into(%{})
    |> encode_payload()
  end

  defp ensure_key_exist(payload) do
    case payload do
      %{"key" => _} -> payload
      %{key: _} -> payload
      _ -> Map.put(payload, "key", "default")
    end
  end

  # Với những field có payload lớn thì nên lưu lại trên disk
  # rồi lưu reference vào index
  defp handle_field_content({:reference, value}) do
    url = "10.1.8.251:5055/references"
    body_parts = [
      {"payload", value}
    ]
    HTTPoison.post(
      url,
      {:multipart, body_parts},
      [{"Content-Type", "multipart/form-data"}]
    )
    |> case do
      {:ok, %{body: body, status_code: 200}} ->
        case Poison.decode(body) do
          {:ok, %{"id" => reference_id}} -> reference_id
          {:error, _} -> :cannot_persist_reference
        end

      {:error, _} -> :cannot_persist_reference
    end
  end

  defp handle_field_content({:json, value}) do
    case Poison.encode(value, pretty: true) do
      {:ok, value} -> value
      {:error, _} -> :cannot_json_encode
    end
  end

  defp handle_field_content(value), do: value

  defp encode_payload(payload) do
    case Poison.encode(payload) do
      {:ok, encoded} -> {:ok, encoded <> "\n"}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule LogCake.Logstash.Connection do
  use Connection
  @app :pancake_log

  def start_link(_) do
    Connection.start_link(__MODULE__, {
      (Application.get_env(@app, :logstash) || [ip: '10.1.8.196', port: 5046]) |> Keyword.get(:ip),
      (Application.get_env(@app, :logstash) || [ip: '10.1.8.196', port: 5046]) |> Keyword.get(:port),
      [send_timeout: 5000], 10000
    })
  end

  def init({host, port, opts, timeout}) do
    state = %{host: host, port: port, opts: opts, timeout: timeout, sock: nil}
    {:connect, :init, state}
  end

  def connect(_, %{sock: nil, host: host, port: port, opts: opts, timeout: timeout} = state) do
    case :gen_tcp.connect(host, port, [active: true] ++ opts, timeout) do
      {:ok, sock} ->
        {:ok, %{state | sock: sock}}

      {:error, _} ->
        {:backoff, 1000, state}
    end
  end

  def disconnect(info, %{sock: sock} = state) do
    :ok = :gen_tcp.close(sock)
    case info do
      {:close, from} ->
        Connection.reply(from, :ok)

      {:error, _reason} -> :ignore
    end

    {:connect, :reconnect, %{state | sock: nil}}
  end

  def handle_info({:tcp_closed, socket}, %{sock: socket} = state) do
    {:disconnect, {:error, :closed}, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  def handle_cast({:send_log, payload}, %{sock: tcp_socket} = state) do
    case :gen_tcp.send(tcp_socket, payload) do
      :ok -> {:noreply, state}

      {:error, :timeout} ->
        {:noreply, state}

      {:error, reason} ->
        {:disconnect, {:error, reason}, state}
    end
  end
end

# operating
