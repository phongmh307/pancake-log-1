defmodule LogCake.CustomLoggerBackends.SentryMode do
  # Enable this mode for auto log all crash to storage
  alias LogCake.Logstash
  defstruct level: nil,
            format: nil,
            metadata: nil,
            log_final_storage: nil,
            logstash_index: nil

  @behaviour :gen_event
  @app :pancake_log

  def test_crash() do
    raise "im gonna crash"
  end

  @impl true
  def init(__MODULE__) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:configure, options}, state) do
    {
      :ok, :ok,
      %{
        state
        | format: Logger.Formatter.compile(Keyword.get(options, :format)), # format default có sẵn trong hàm moudle Logger,
          metadata: Keyword.get(options, :metadata, []) |> Keyword.put_new(:node, Node.self()),
          level: Keyword.get(options, :level, :warning),
          log_final_storage: Keyword.get(options, :log_final_storage), # Đây là require config đã được check trước
          logstash_index: Keyword.get(options, :logstash_index)
      }
    }
  end

  @impl true
  def handle_event(
    {level, _gl, {Logger, msg, ts, _md}},
    %__MODULE__{
      level: log_level,
      format: log_format,
      metadata: log_metadata,
      log_final_storage: log_final_storage,
      logstash_index: logstash_index
    } = state
  ) do
    if meet_level?(level, log_level) do
      Enum.each(log_final_storage, fn storage ->
        case storage do
          :s3 -> :not_supported_yet
          :logstash ->
            log_metadata
            |> Enum.into(%{})
            |> Map.merge(%{
              key: logstash_index,
              message: :unicode.characters_to_binary(msg)
            })
            |> Logstash.log()
        end
      end)
    else
      {:ok, state}
    end
    {:ok, state}
  end

  defp meet_level?(_lvl, nil), do: true

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end
end
