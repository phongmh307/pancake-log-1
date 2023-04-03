defmodule LogCake.Application do
  use Application
  require Logger

  @app :pancake_log

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    if System.get_env("DEV_MODE") do
      Application.put_env(@app, :log_final_storage, [:logstash])
      Application.put_env(@app, :enable_sentry_mode, true)
      Application.put_env(@app, :logstash, [ip: '10.1.8.196', port: 5046])
      Application.put_env(
        @app,
        LogCake.CustomLoggerBackends.SentryMode,
        [level: :error, metadata: [node: Node.self()], logstash_index: "botcake_local_crash"]
      )
    end

    ensure_config_respectable()

    if Application.get_env(@app, :enable_sentry_mode) do
      Logger.add_backend(LogCake.CustomLoggerBackends.SentryMode)
      Logger.configure_backend(
        LogCake.CustomLoggerBackends.SentryMode,
        Application.get_env(@app, LogCake.CustomLoggerBackends.SentryMode, [])
        |> Keyword.take([:format, :level, :metadata, :logstash_index])
        |> Keyword.put(:log_final_storage, Application.get_env(@app, :log_final_storage))
      )
    end

    append_children_for =
      fn final_storage ->
        case final_storage do
          :s3 ->
            s3_configs = Application.get_env(@app, :s3)

            storage_path = Keyword.get(s3_configs, :storage_path)
            File.mkdir_p!(storage_path)
            endpoint_opts = [port: Keyword.get(s3_configs, :adapter_port)]
            [
              {LogCake.Endpoint, endpoint_opts},
              {LogCake.LogDeviceMaster, []},
              {Task, &LogCake.LogDeviceMaster.init_child/0}
            ]
          :logstash ->
            logstash_configs = Application.get_env(@app, :logstash)

            if Keyword.get(logstash_configs, :use_logcake_logstash?, true) do
              # [{LogCake.Logstash, :start_link}]
              [
                supervisor(LogCake.Logstash, [])
              ]
            else
              []
            end
        end
      end

    children =
      Application.get_env(@app, :log_final_storage)
      |> Enum.filter(& &1 in [:s3, :logstash])
      |> Enum.reduce([], &(&2 ++ append_children_for.(&1)))

    opts = [strategy: :one_for_one, name: LogCake.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_config_respectable() do
    do_ensure_generic_config_respectable()

    case Application.get_env(@app, :log_final_storage) do
      log_final_storage when is_list(log_final_storage) ->
        log_final_storage
        |> Enum.filter(& &1 in [:s3, :logstash])
        |> Enum.each(& do_ensure_config_respectable(for_final_storage: &1))
      _ ->
        raise(ArgumentError,
          message: "LogCake(Required Config): We provide 2 log_final_storage: (:logstash || :s3) "
                   <> "you can use one or both of them"
        )
    end
  end

  defp do_ensure_generic_config_respectable() do
    Logger.info(
      "LogCake: log_final_storage selection suggestion. :s3 is good "
      <> "for operating logs, :logstash is good for bug logs"
    )
    # enable_sentry_mode = Application.get_env(@app, :enable_sentry_mode)

    # if enable_sentry_mode === true do
    # else
    #   Logger.info(
    #     "LogCake: We provide Sentry mode for logging all info about "
    #     <> "crash process, if you want to use it, add config"
    #     <> "(enable_sentry_mode: true) in #{@app} config"
    #   )
    # end

    with  {_, enable_sentry_mode} when enable_sentry_mode == true <- {:enable_sentry_mode, Application.get_env(@app, :enable_sentry_mode)},
          {_, used_logstash_storage?} when used_logstash_storage? == true <- (
            {
              :used_logstash_storage?,
              Application.get_env(@app, :log_final_storage)
              |> Enum.any?(& &1 == :logstash)
            }
          ),
          {_, logstash_index} when is_binary(logstash_index) <- (
            {
              :logstash_index,
              Application.get_env(@app, LogCake.CustomLoggerBackends.SentryMode, [])
              |> Keyword.get(:logstash_index)
            }
          ) do
      :ok
    else
      {:enable_sentry_mode, _} ->
        Logger.info(
          "LogCake: We provide Sentry mode for logging all info about "
          <> "crash process, if you want to use it, add config"
          <> "(enable_sentry_mode: true) in #{@app} config"
        )
      {:used_logstash_storage, _} ->
        raise(ArgumentError,
          message: "LogCake(Sentry_mode)(Required Config): For now we support only storage :logstash for "
                   <> "crash log of sentry_mode"
        )
      {:logstash_index, _} ->
        raise(ArgumentError,
          message: "LogCake(Sentry_mode)(Required Config): You must config :logstash_index (for crash log)"
        )
    end
  end

  defp do_ensure_config_respectable(for_final_storage: :s3) do
    s3_configs = Application.get_env(@app, S3)
    if !Keyword.get(s3_configs, :adapter_port),
      do:
        raise(ArgumentError,
          message: "Missing adapter_port in #{@app} application config"
        )

    if !Keyword.get(s3_configs, :storage_path),
      do:
        raise(ArgumentError,
          message: "Missing storage_path in #{@app} application config"
        )
  end

  defp do_ensure_config_respectable(for_final_storage: :logstash) do
    logstash_configs = Application.get_env(@app, :logstash)
    if Keyword.get(logstash_configs, :use_logcake_logstash?, true) do
      with {_, ip} when ip != nil <- {:ip, Keyword.get(logstash_configs, :ip)},
           {_, port} when port != nil <- {:port, Keyword.get(logstash_configs, :port)} do
        :ok
      else
        {:ip, _} ->
          raise(ArgumentError,
            message: "Missing :ip in :pancake_log(Logcake.Logstash) config"
          )
        {:port, _} ->
          raise(ArgumentError,
            message: "Missing :port in :pancake_log(Logcake.Logstash) config"
          )
      end
    else
      case Keyword.get(logstash_configs, :mf_logstash) do
        {_module, _function} ->
          :ok
        _ ->
          raise(ArgumentError,
            message: "Missing :mf_logstash(module, function of your logstash) in "
                     <> ":pancake_log(Logcake.Logstash) config"
          )
      end
    end
  end
end
