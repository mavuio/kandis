defmodule Kandis.Mock.Repo do
  use Ecto.Repo,
    otp_app: :kandis,
    adapter: Ecto.Adapters.MyXQL
end
