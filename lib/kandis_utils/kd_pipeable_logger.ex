defmodule Kandis.KdPipeableLogger do
  require Logger

  def debug(data, msg \\ "", metadata \\ [])
  def debug(data, msg, metadata) when msg == "", do: Logger.debug(data, metadata)

  def debug(data, msg, metadata) when is_binary(data) do
    Logger.debug(msg <> " " <> data, metadata)
    data
  end

  def debug(data, msg, metadata) do
    Logger.debug(msg <> inspect(data), metadata)
    data
  end

  def warn(data, msg \\ "", metadata \\ [])
  def warn(data, msg, metadata) when msg == "", do: Logger.warn(data, metadata)

  def warn(data, msg, metadata) when is_binary(data) do
    Logger.warn(msg <> " " <> data, metadata)
    data
  end

  def warn(data, msg, metadata) do
    Logger.warn(msg <> inspect(data), metadata)
    data
  end

  def error(data, msg \\ "", metadata \\ [])
  def error(data, msg, metadata) when msg == "", do: Logger.error(data, metadata)

  def error(data, msg, metadata) when is_binary(data) do
    Logger.error(msg <> " " <> data, metadata)
    data
  end

  def error(data, msg, metadata) do
    Logger.error(msg <> inspect(data), metadata)
    data
  end

  def info(data, msg \\ "", metadata \\ [])
  def info(data, msg, metadata) when msg == "", do: Logger.info(data, metadata)

  def info(data, msg, metadata) when is_binary(data) do
    Logger.info(msg <> " " <> data, metadata)
    data
  end

  def info(data, msg, metadata) do
    Logger.info(msg <> inspect(data), metadata)
    data
  end
end
