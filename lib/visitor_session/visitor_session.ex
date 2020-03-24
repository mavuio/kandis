defmodule Kandis.VisitorSession do
  @moduledoc false
  alias Kandis.VisitorSessionGenServer

  # public API:
  defdelegate get_data(sid), to: VisitorSessionGenServer

  defdelegate set_data(sid, data), to: VisitorSessionGenServer

  defdelegate set_value(sid, key, value), to: VisitorSessionGenServer

  defdelegate get_value(sid, key, default \\ nil), to: VisitorSessionGenServer

  def merge_into(sid, key, values) when is_map(values) do
    merged =
      get_value(sid, key, %{})
      |> Map.merge(values)

    set_value(sid, key, merged)
    merged
  end

  def clean_and_archive(sid, empty_data_record, archive_sid)
      when is_map(empty_data_record) and is_binary(archive_sid) do
    data = get_data(sid)

    archive_data = data
    new_data = data |> Map.merge(empty_data_record)

    VisitorSessionGenServer.save_data_to_db(archive_sid, archive_data)
    set_data(sid, new_data)
  end
end
