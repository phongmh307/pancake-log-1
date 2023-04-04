defmodule LogCake.Application do
  use Application
  require Logger

  @app :pancake_log

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    if System.get_env("DEV_MODE") do
      Application.put_env(@app, :log_final_storage, [:s3, :logstash])
      Application.put_env(@app, :enable_sentry_mode, true)
      Application.put_env(
        @app,
        :sentry_mode,
        [logstash_index: "botcake_local_crash"]
      )
      Application.put_env(@app, :s3, [storage_path: "./test_log", adapter_port: 4010])
    end

    ensure_config_respectable()

    if Application.get_env(@app, :enable_sentry_mode) do
      Logger.add_backend(LogCake.CustomLoggerBackends.SentryMode)
      Logger.configure_backend(
        LogCake.CustomLoggerBackends.SentryMode,
        Application.get_env(@app, :sentry_mode, [])
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
            logstash_configs =
              case Application.get_env(@app, :logstash) do
                logstash when is_list(logstash) ->
                  logstash
                  |> Keyword.put_new(:use_logcake_logstash?, true)
                  |> Keyword.put_new(:ip, '10.1.8.196')
                  |> Keyword.put_new(:port, 5046)
                _ ->
                  [
                    use_logcake_logstash?: true,
                    ip: '10.1.8.196',
                    port: 5046
                  ]
              end

            :persistent_term.put(
              {LogCake.Logstash, :use_logcake_logstash?},
              Keyword.get(logstash_configs, :use_logcake_logstash?)
            )

            if Keyword.get(logstash_configs, :use_logcake_logstash?) do
              [%{
                id: LogCake.Logstash,
                start: {
                  LogCake.Logstash,
                  :start_link,
                  [logstash_configs]
                }
              }]
            else
              :persistent_term.put(
                {LogCake.Logstash, :mf_logstash},
                Keyword.get(logstash_configs, :mf_logstash)
              )
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
          message: "#{__MODULE__}(Required Config): We provide 2 log_final_storage: (:logstash || :s3) "
                   <> "you can use one or both of them"
        )
    end
  end

  defp do_ensure_generic_config_respectable() do
    Logger.info(
      "#{__MODULE__}: log_final_storage selection suggestion. :s3 is good "
      <> "for operating logs, :logstash is good for bug logs"
    )

    with  {_, enable_sentry_mode} when enable_sentry_mode == true <- {:enable_sentry_mode, Application.get_env(@app, :enable_sentry_mode)},
          {_, used_logstash_storage?} when used_logstash_storage? == true <- (
            {
              :used_logstash_storage?,
              Enum.any?(
                Application.get_env(@app, :log_final_storage),
                & &1 == :logstash
              )
            }
          ),
          {_, logstash_index} when is_binary(logstash_index) <- (
            {
              :logstash_index,
              Keyword.get(
                Application.get_env(@app, :sentry_mode, []),
                :logstash_index
              )
            }
          ) do
      :ok
    else
      {:enable_sentry_mode, _} ->
        Logger.info(
          "#{__MODULE__}: We provide Sentry mode for logging all info about "
          <> "crash process, if you want to use it, add config"
          <> "(enable_sentry_mode: true) in #{@app} config"
        )
      {:used_logstash_storage?, _} ->
        raise(ArgumentError,
          message: "#{__MODULE__}(Sentry_mode)(Required Config): For now we support only storage :logstash for "
                   <> "crash log of sentry_mode"
        )
      {:logstash_index, _} ->
        raise(ArgumentError,
          message: "#{__MODULE__}(Sentry_mode)(Required Config): You must config :logstash_index (for crash log)"
        )
    end
  end

  defp do_ensure_config_respectable(for_final_storage: :s3) do
    if s3_configs = Application.get_env(@app, :s3) do
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
    else
      raise(ArgumentError,
            message: "Missing s3 config in #{@app} application config"
      )
    end
  end

  defp do_ensure_config_respectable(for_final_storage: :logstash) do
    with  logstash_configs when is_list(logstash_configs) <- Application.get_env(@app, :logstash),
          true <- Keyword.get(logstash_configs, :use_logcake_logstash?) == false do
      case Keyword.get(logstash_configs, :mf_logstash) do
        {module, function} when is_atom(module) and is_atom(function) ->
          :ok
        _ ->
          raise(ArgumentError,
            message: "#{__MODULE__}: Missing :mf_logstash(module, function of your logstash) in "
                      <> ":pancake_log(:logstash) config"
          )
      end
    else
      _ -> :ok
    end
  end
end
