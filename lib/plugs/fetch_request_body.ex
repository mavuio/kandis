defmodule Kandis.Plugs.FetchRequestBody do
  @moduledoc "Get public IP address of request from x-forwarded-for header"
  @behaviour Plug

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    body |> IO.inspect(label: "KANDIS READBODY")
    conn |> Plug.Conn.put_private(:raw_body, body)
  end

  def read_cached_body(conn) do
    conn.private[:raw_body]
  end
end
