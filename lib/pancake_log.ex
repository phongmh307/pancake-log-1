defmodule LogCake do
  @moduledoc """
  Module chứa interface để thao tác với LogCake client
  """

  defmodule LogDeviceHolder do
    use GenServer

    def start_link(device_path) do
      GenServer.start(__MODULE__, [device_path], name: Module.concat(__MODULE__, device_path))
    end

    def get_io_device(device_path) do
      GenServer.call(Module.concat(__MODULE__, device_path), :get_io_device)
    end

    def health_check(device_path) do
      GenServer.cast(Module.concat(__MODULE__, device_path), :health_check)
    end

    @impl true
    @heal_check_interval 15_000
    def init(device_path) do
      open_device(device_path)
      :timer.apply_interval(@heal_check_interval, __MODULE__, :health_check, [device_path])
      {:ok, nil}
    end

    defp open_device(device_path) do
      File.open!(device_path, [:delayed_write, :append])
    end

    @impl true
    def handle_call(:get_io_device, _from, io_device) do
      {:reply, io_device}
    end

    @impl true
    def handle_cast({:health_check, device_path}, io_device) do
      case :file.read(io_device, 0) do
        {:ok, _} -> {:noreply, io_device}
        {:error, _} -> {:noreply, open_device(device_path)}
      end
    end
  end

  @storage_path Application.get_env(:pancake_log, :storage_path, "./log_vcl")
  # 10 mins
  @shard_interval 600

  @doc """
  Log 1 entry. Cấu trúc của 1 log entry bao gồm metadata và payload

  `metadata` được cấu trúc bởi các cặp key-value. Ví dụ: page_id=123, user_id=456

  `payload` là nội dung binary cần log

  ## Ví dụ

      iex> LogCake.log("My payload", a: 1, b: 2)
      :ok

  """
  @type log_payload :: binary() | iodata()
  @spec log(log_payload(), list()) :: :ok
  def log(payload, metadata \\ []) do
    path = current_path()
    io_device = LogDeviceHolder.get_io_device(path)
    IO.binwrite(io_device, construct_log_payload(payload, metadata))
    :ok
  end

  @compile {:inline, current_path: 0}
  defp current_path do
    shard_id = div(System.os_time(:second), @shard_interval) * @shard_interval
    file_name = "#{Integer.to_string(shard_id)}_#{Integer.to_string(shard_id + @shard_interval)}"
    Path.join(@storage_path, file_name)
  end

  # Format như sau:
  # - 4 bytes chỉ định độ lớn của payload. Nghĩa là độ lớn tối đa của payload là ~4GB
  # - 2 bytes chỉ định độ lớn của metadata. Nghĩa là độ lớn tối đa của metadata là ~65KB
  # - metadata bytes
  # - payload bytes
  defp construct_log_payload(payload, metadata) do
    io_metadata =
      metadata
      |> Keyword.put(:timestamp, NaiveDateTime.utc_now |> NaiveDateTime.truncate(:millisecond) |> to_string)
      |> Enum.reduce([], fn {key, value}, acc ->
        if !is_binary(value) and !is_integer(value),
          do: raise(RuntimeError, message: "metadata value must be a binary or a integer")

        value = if is_integer(value), do: Integer.to_string(value), else: value
        io = [Atom.to_string(key), <<1>>, value]
        if acc == [], do: io, else: [io, 0 | acc]
      end)

    io_metadata_size = IO.iodata_length(io_metadata)

    payload_size =
      cond do
        is_binary(payload) -> byte_size(payload)
        is_list(payload) -> IO.iodata_length(payload)
      end

    [<<payload_size::32>>, <<io_metadata_size::16>>, io_metadata, payload]
  end
end
