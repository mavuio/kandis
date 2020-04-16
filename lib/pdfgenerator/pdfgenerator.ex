defmodule Kandis.Pdfgenerator do
  alias Kandis.Order
  import Kandis.KdHelpers, warn: false
  @moduledoc false

  @get_invoice_template_url Application.get_env(:kandis, :get_invoice_template_url)

  def get_pdf_file_for_invoice_nr(invoice_nr, params \\ %{}) do
    filename = get_filename_for_invoice_nr(invoice_nr)

    case File.exists?(filename) and is_nil(params["regenerate"]) do
      true ->
        filename

      false ->
        generated_filename = generate_invoice_pdf(invoice_nr)

        if generated_filename == filename do
          filename
        else
          raise "filenames do not match #{generated_filename} vs #{filename}"
        end
    end
  end

  def get_filename_for_invoice_nr(invoice_nr) when is_binary(invoice_nr) do
    invoice_dir = Application.get_env(:kandis, :invoice_dir)
    filename = "rg_#{invoice_nr}.pdf"
    "#{invoice_dir}/#{filename}"
  end

  def generate_invoice_pdf(any_order_id) do
    with order when is_map(order) <- Order.get_by_any_id(any_order_id),
         html_url when is_binary(html_url) <- get_invoice_template_url(order.order_nr),
         filename when is_binary(filename) <- get_filename_for_invoice_nr(order.invoice_nr),
         cloud_url when is_binary(cloud_url) <- generate_pdf_in_cloud(html_url, filename),
         {:ok, filename} when is_binary(filename) <- store_pdf_locally(cloud_url, filename) do
      filename
    end
  end

  def get_invoice_template_url(order_nr) when is_binary(order_nr),
    do: @get_invoice_template_url.(order_nr)

  def generate_pdf_in_cloud(html_url, filename)
      when is_binary(html_url) and is_binary(filename) do
    json = generate_json_options(%{url: html_url, fileName: filename})

    make_request(json)
    |> case do
      {:ok, response} -> response.body |> Jason.decode!() |> Map.get("pdf")
      _ -> nil
    end
  end

  def get_url_for_file(filename) do
    String.replace_leading(
      filename,
      Application.get_env(:evablut, :config)[:invoice_dir],
      Application.get_env(:evablut, :config)[:invoice_url]
    )
  end

  def store_pdf_locally(remote_pdf_url, filename) do
    {remote_pdf_url, filename}
    |> IO.inspect(
      label: "mwuits-debug 2020-03-29_23:51 store_pdf_locally(remote_pdf_url, filename) "
    )

    if File.exists?(filename) do
      :ok = File.rm(filename)
    end

    Download.from(remote_pdf_url, path: filename)
  end

  def generate_json_options(addon_opts) do
    %{
      url: nil,
      fileName: "test.pdf",
      options: %{
        landscape: "false",
        printBackground: false
      }
    }
    |> Map.merge(addon_opts)
    |> Jason.encode!()
  end

  def make_request(body) do
    base_url = Application.get_env(:evablut, :api2pdf)[:base_url]
    api_key = Application.get_env(:evablut, :api2pdf)[:api_key]
    url = "#{base_url}/chrome/url/" |> IO.inspect(label: "mwuits-debug 2020-03-29_12:07 ")

    HTTPoison.post(url, body, Authorization: api_key)
  end
end
