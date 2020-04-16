use Mix.Config

config :kandis,
  local_checkout: Kandis.Mock.LocalCheckout,
  local_cart: Kandis.Mock.LocalCart

import_config "#{Mix.env()}.exs"
