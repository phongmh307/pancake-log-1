defmodule LogCake do
  @moduledoc """
  Module chứa interface để thao tác với LogCake client
  """

  defmodule LogDeviceHolder do
    use GenServer

    def start_link(device_path) do
      GenServer.start_link(__MODULE__, device_path, name: Module.concat(__MODULE__, device_path))
    end

    def get_io_device(device_path) do
      GenServer.call(Module.concat(__MODULE__, device_path), :get_io_device)
    end

    @impl true
    def init(device_path) do
      io_device = open_device(device_path)
      {:ok, {device_path, io_device}}
    end

    @impl true
    def handle_call(:get_io_device, _from, {_device_path, io_device} = state) do
      {:reply, io_device, state}
    end

    @impl true
    def handle_call(:get_device_path, _from, {device_path, _io_device} = state) do
      {:reply, device_path, state}
    end

    defp open_device(device_path) do
      File.open!(device_path, [:delayed_write, :append])
    end
  end

  # 10 mins
  defmodule LogDeviceMaster do
    alias LogCake.LogDeviceHolder
    use DynamicSupervisor

    def start_link(args) do
      DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
    end

    def init_child() do
      for child <- generate_necessary_log_holder_paths(System.os_time(:second)) do
        start_child(child)
      end
      :ok
    end

    def start_child(shard_time) do
      DynamicSupervisor.start_child(__MODULE__, {LogDeviceHolder, shard_time})
    end

    def test() do
      DynamicSupervisor.which_children(__MODULE__)
    end

    def handle_device_holder() do
      neccessary_log_holder_paths = generate_necessary_log_holder_paths(System.os_time(:second))
      survived_log_holder_paths =
        __MODULE__
        |> DynamicSupervisor.which_children()
        |> Enum.reduce([], fn {_, pid, _type_pid, _params}, acc ->
          device_path =
            pid
            |> Process.info()
            |> Keyword.get(:registered_name)
            |> GenServer.call(:get_device_path)

          if device_path not in neccessary_log_holder_paths do
            DynamicSupervisor.terminate_child(__MODULE__, pid)
            File.rm_rf!(device_path)
            acc
          else
            acc ++ [device_path]
          end
        end)

      neccessary_log_holder_paths
      |> Kernel.--(survived_log_holder_paths)
      |> Enum.each(fn new_child_path ->
        DynamicSupervisor.start_child(__MODULE__, {LogDeviceHolder, new_child_path})
      end)
    end

    @shard_interval 600
    @interval_checking_holder 120_000
    def init(_) do
      :timer.apply_interval(
        @interval_checking_holder,
        __MODULE__,
        :handle_device_holder,
        []
      )
      DynamicSupervisor.init(strategy: :one_for_one)
    end

    defp generate_necessary_log_holder_paths(time) do
      [
        LogCake.path(time - 2 * @shard_interval),
        LogCake.path(time - @shard_interval),
        LogCake.path(time),
        LogCake.path(time + @shard_interval),
        LogCake.path(time + 2 * @shard_interval)
      ]
    end
  end

  @storage_path Application.get_env(:pancake_log, :storage_path, "./test_log")

  @doc """
  Log 1 entry. Cấu trúc của 1 log entry bao gồm metadata và payload

  `metadata` được cấu trúc bởi các cặp key-value. Ví dụ: page_id=123, user_id=456

  `payload` là nội dung binary cần log

  ## Ví dụ

      iex> LogCake.log("My payload", a: 1, b: 2)
      :ok

  """

  def log(payload) when is_map(payload) do
    LogCake.Logstash.log(payload)
  end

  @type log_payload :: binary() | iodata()
  @spec log(log_payload(), list()) :: :ok
  def log(payload, metadata \\ []) do
    path = path(System.os_time(:second))
    io_device = LogDeviceHolder.get_io_device(path)
    IO.binwrite(io_device, construct_log_payload(payload, metadata))
    :ok
  end

  def do_log(:s3, payload, metadata \\ []) do
    path = path(System.os_time(:second))
    io_device = LogDeviceHolder.get_io_device(path)
    IO.binwrite(io_device, construct_log_payload(payload, metadata))
    :ok
  end

  @shard_interval 600
  # @compile {:inline, path: 0}
  def path(time) do
    shard_id = div(time, @shard_interval) * @shard_interval
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
