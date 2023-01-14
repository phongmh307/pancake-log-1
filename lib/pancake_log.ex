defmodule LogCake do
  @moduledoc """
  Module chứa interface để thao tác với LogCake client
  """

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
    io_device = get_io_device(path)
    IO.binwrite(io_device, construct_log_payload(payload, metadata))
    :ok
  end

  @compile {:inline, current_path: 0}
  defp current_path do
    shard_id = div(System.os_time(:second), @shard_interval) * @shard_interval
    file_name = "#{Integer.to_string(shard_id)}_#{Integer.to_string(shard_id + @shard_interval)}"
    Path.join(@storage_path, file_name)
  end

  @compile {:inline, get_io_device: 1}
  defp get_io_device(path) do
    key = {__MODULE__, :io_device, path}
    io_device = :persistent_term.get(key, nil)

    if io_device do
      io_device
    else
      # Có thể race-condition ở đây, có thể bỏ qua vì không nghiêm trọng
      io_device = File.open!(path, [:delayed_write, :raw, :append])
      :persistent_term.put(key, io_device)
      io_device
    end
  end

  # Format như sau:
  # - 4 bytes chỉ định độ lớn của payload. Nghĩa là độ lớn tối đa của payload là ~4GB
  # - 2 bytes chỉ định độ lớn của metadata. Nghĩa là độ lớn tối đa của metadata là ~65KB
  # - payload bytes
  # - metadata bytes
  defp construct_log_payload(payload, metadata) do
    io_metadata =
      Enum.reduce(metadata, [], fn {key, value}, acc ->
        if !is_binary(value) and !is_integer(value),
          do: raise(RuntimeError, message: "metadata value must be a binary or a integer")

        value = if is_integer(value), do: Integer.to_string(value), else: value
        io = [Atom.to_string(key), "=", value]
        if acc == [], do: io, else: [io, 0 | acc]
      end)

    io_metadata_size = IO.iodata_length(io_metadata)

    payload_size =
      cond do
        is_binary(payload) -> byte_size(payload)
        is_list(payload) -> IO.iodata_length(payload)
      end

    [<<payload_size::32>>, <<io_metadata_size::16>>, payload, io_metadata]
  end
end
