defmodule Kandis.KdStash do
  use GenServer

  require Logger

  @maxitems 10

  ## Client API

  @doc """
  Starts the Stash.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds item to the stash
  """
  def add(server \\ __MODULE__, payload, label) do
    GenServer.cast(server, {:add, payload, label})
    payload
  end

  @doc """
  List stash items
  """

  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  def get(server \\ __MODULE__, key)

  def get(server, key) when is_atom(key) do
    get(server, Atom.to_string(key))
  end

  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  ## ----------------------------------- server:

  def init(_opts) do
    Logger.info("MwStash started")
    {:ok, []}
  end

  def handle_call(:list, _from, items) do
    list =
      items
      |> Stream.with_index()
      |> Enum.map(fn {{key, _payload, label}, idx} ->
        "#{idx}  #{key}  ➜  #{label}"
      end)
      |> Enum.join("\n")
      |> MwHelpers.log()

    {:reply, list, items}
  end

  def handle_call({:get, key}, _from, items) when is_binary(key) do
    item = items |> Enum.find(&(&1 |> elem(0) == key))

    ret =
      case item do
        {_key, payload, _label} -> payload
        _ -> nil
      end

    {:reply, ret, items}
  end

  def handle_call({:get, idx}, _from, items) when is_integer(idx) do
    item = items |> Enum.at(idx)

    ret =
      case item do
        {_key, payload, _label} -> payload
        _ -> nil
      end

    {:reply, ret, items}
  end

  def handle_cast({:add, payload, label}, state) do
    newstate = add_to_stack(state, payload, label)
    {:noreply, newstate}
  end

  defp add_to_stack(stack, payload, label) do
    key = new_key()

    Logger.info("\"#{key}\" ➜ #{label}  ... item was added to MwStash ")

    [{key, payload, label} | stack] |> Enum.take(@maxitems)
  end

  defp new_key() do
    "abcdefghjkmnopqrstuvwxyz0123456789"
    |> String.graphemes()
    |> Enum.take_random(2)
    |> Enum.join()
  end
end
