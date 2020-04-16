use Mix.Config

config :kandis,
  repo: Kandis.Mock.Repo,
  pubsub: Kandis.Mock,
  local_checkout: Kandis.Mock,
  local_cart: Kandis.Mock,
  local_order: Kandis.Mock,
  server_view: Kandis.Mock,
  order_record: Kandis.Mock.OrderRecord,
  translation_function: &Kandis.Mock.t/3,
  get_invoice_template_url: &Kandis.Mock.get_invoice_template_url/1,
  invoice_nr_prefix: "EBS",
  invoice_nr_testprefix: "EBT",
  steps_module_path: "EvablutWeb.Shop.Checkout.Steps",
  payments_module_path: "EvablutWeb.Shop.Payments"
