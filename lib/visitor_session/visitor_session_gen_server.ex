defmodule Kandis.VisitorSessionGenServer do
  use GenServer
  require Logger
  alias Kandis.VisitorSessionSupervisor
  alias Kandis.LiveUpdates
  alias Kandis.VisitorSessionStore
  @repo Application.get_env(:kandis, :repo)

  import Kandis.KdHelpers, warn: false

  @registry :kandis_visitor_session_registry

  defstruct sid: nil,
            email: nil,
            data: %{}

  use Accessible

  ## API
  def start_link(sid),
    do: GenServer.start_link(__MODULE__, sid, name: via_tuple(sid))

  def stop(sid), do: GenServer.cast(via_tuple(sid), :stop)

  def get_data(sid), do: GenServer.call(get_pid(sid), :get_data)

  def get_value(sid, key, default \\ nil)

  def get_value(nil, _, _), do: nil

  def get_value(sid, key, default) when is_binary(sid) and is_binary(key),
    do: GenServer.call(get_pid(sid), {:get_value, key, default})

  def set_value(sid, key, value) when is_binary(sid) and is_binary(key),
    do: GenServer.call(get_pid(sid), {:set_value, key, value})

  def set_data(sid, data) when is_binary(sid) and is_map(data),
    do: GenServer.call(get_pid(sid), {:set_data, data})

  ## Callbacks
  @impl true
  def init(sid) do
    log("❖ init visitorsession '#{sid}'")
    send(self(), :fetch_data)
    {:ok, %__MODULE__{sid: sid}}
  end

  @impl true
  def handle_cast(:work, sid) do
    Logger.info("hola")
    {:noreply, sid}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_cast(:raise, sid),
    do: raise(RuntimeError, message: "Error, Server #{sid} has crashed")

  @impl true
  def handle_call(:get_data, _from, state) do
    response = state.data
    {:reply, response, state}
  end

  def handle_call({:get_value, key, default}, _from, state) do
    response =
      get_in(state, [:data | get_key_parts(key)])
      |> case do
        nil -> default
        val -> val
      end

    {:reply, response, state}
  end

  def handle_call({:set_value, key, value}, _from, state) do
    # value |> IO.inspect(label: "mwuits-debug 2020-03-15_12:05 visitor-session SET ")

    state =
      put_in(
        state,
        [
          :data
          # create emoty map s default
          | Enum.map(get_key_parts(key), &Access.key(&1, %{}))
        ],
        value
      )

    LiveUpdates.notify_live_view(
      state.sid,
      {:visitor_session, [key, :updated], value}
    )

    save_data_to_db(state.sid, state.data)
    response = :ok
    {:reply, response, state}
  end

  def handle_call({:set_data, data}, _from, state) do
    state = put_in(state, [:data], data)

    LiveUpdates.notify_live_view(
      state.sid,
      {:visitor_session, [:all, :updated], nil}
    )

    save_data_to_db(state.sid, state.data)
    response = :ok
    {:reply, response, state}
  end

  @doc """
  fetch data from db:
  """
  def handle_info(:fetch_data, state) do
    updated_state =
      if is_nil(@repo) do
        state
      else
        fetch_data_from_db(state.sid)
        |> case do
          nil -> state
          data_from_db -> %__MODULE__{state | data: data_from_db}
        end
      end

    {:noreply, updated_state}
  end

  @impl true
  def terminate(reason, _state) do
    reason
    |> IO.inspect(label: "mwuits-debug 2020-03-18_11:24 Visitor Session  exits with reason ")

    log(
      reason,
      "mwuits-debug 2018-08-10_22:15 Visitor Session  exits with reason",
      :warn
    )
  end

  ## Private
  defp via_tuple(sid),
    do: {:via, Registry, {@registry, sid}}

  defp get_pid(sid) do
    VisitorSessionSupervisor.find_or_create_child(sid)
  end

  defp get_key_parts(key_str) when is_binary(key_str) do
    key_str |> String.split(["."])
  end

  def fetch_data_from_db(sid) do
    case @repo.get_by(VisitorSessionStore, sid: sid) do
      nil -> nil
      rec -> rec.state |> Bertex.decode()
    end
  end

  def save_data_to_db(sid, data) do
    case @repo.get_by(VisitorSessionStore, sid: sid) do
      nil -> %VisitorSessionStore{sid: sid}
      rec -> rec
    end
    |> VisitorSessionStore.changeset(%{state: data |> Bertex.encode()})
    |> @repo.insert_or_update()
  end
end
