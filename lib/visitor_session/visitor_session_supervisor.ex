defmodule Kandis.VisitorSessionSupervisor do
  use DynamicSupervisor
  alias Kandis.VisitorSessionGenServer
  import Kandis.KdHelpers, warn: false

  @registry :kandis_visitor_session_registry

  def start_link(_arg),
    do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  def init(_arg),
    do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc false

  def find_or_create_child(sid) when is_binary(sid) do
    case get_pid_of_child(sid) do
      nil ->
        case create_child(sid) do
          {:ok, pid} -> pid
          _ -> nil
        end

      pid ->
        pid
    end
  end

  @doc false
  def get_pid_of_child(sid) when is_binary(sid) do
    case Registry.lookup(@registry, sid) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc false
  def create_child(sid) when is_binary(sid) do
    spec = %{
      id: VisitorSessionGenServer,
      start: {VisitorSessionGenServer, :start_link, [sid]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        pid
        |> log("created child for #{sid} with PID: ")

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:error, :process_already_exists, pid}

      other ->
        {:error, other}
    end
  end
end
