defmodule Kandis.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Kandis.VisitorSessionSupervisor, []},
      {Registry, [keys: :unique, name: :kandis_visitor_session_registry]}
    ]

    opts = [strategy: :one_for_one, name: Kandis.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
