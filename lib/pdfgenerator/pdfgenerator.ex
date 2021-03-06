defmodule Kandis.Pdfgenerator do
  alias Kandis.Order
  import Kandis.KdHelpers, warn: false
  @moduledoc false

  @get_pdf_template_url Application.get_env(:kandis, :get_pdf_template_url)

  def get_pdf_file_for_invoice_nr(invoice_nr, mode, params \\ %{}) when is_binary(mode) do
    filename = get_filename_for_invoice_nr(invoice_nr, mode)

    case File.exists?(filename) and is_nil(params["regenerate"]) do
      true ->
        filename

      false ->
        generated_filename = generate_invoice_pdf(mode, invoice_nr)

        if generated_filename == filename do
          filename
        else
          raise "filenames do not match #{generated_filename} vs #{filename}"
        end
    end
  end

  def get_pdf_file_for_order_nr(order_nr, mode, params \\ %{}) when is_binary(mode) do
    filename = get_filename_for_order_nr(order_nr, mode)

    case File.exists?(filename) and is_nil(params["regenerate"]) do
      true ->
        filename

      false ->
        generated_filename = generate_order_pdf(mode, order_nr)

        if generated_filename == filename do
          filename
        else
          raise "problem while generating pdf"
        end
    end
  end

  def get_filename_for_invoice_nr(invoice_nr, mode)
      when is_binary(invoice_nr) and is_binary(mode) do
    pdf_dir = Application.get_env(:kandis, :pdf_dir)
    filename = "#{mode}_#{invoice_nr}.pdf"
    "#{pdf_dir}/#{filename}"
  end

  def get_filename_for_order_nr(order_nr, mode) when is_binary(order_nr) and is_binary(mode) do
    pdf_dir = Application.get_env(:kandis, :pdf_dir)
    filename = "#{mode}_#{order_nr}.pdf"
    "#{pdf_dir}/#{filename}"
  end

  def generate_invoice_pdf(mode, any_order_id) when is_binary(mode) do
    any_order_id |> Kandis.KdHelpers.log("generate_invoice_pdf #{mode}", :info)

    with order when is_map(order) <- Order.get_by_any_id(any_order_id),
         html_url when is_binary(html_url) <- get_pdf_template_url(order.order_nr, mode),
         filename when is_binary(filename) <- get_filename_for_invoice_nr(order.invoice_nr, mode),
         cloud_url when is_binary(cloud_url) <- generate_pdf_in_cloud(html_url, filename),
         {:ok, filename} when is_binary(filename) <- store_pdf_locally(cloud_url, filename) do
      filename
    end
  end

  def generate_order_pdf(mode, any_order_id) when is_binary(mode) do
    any_order_id |> Kandis.KdHelpers.log("generate_order_pdf #{mode}", :info)

    with order when is_map(order) <- Order.get_by_any_id(any_order_id),
         html_url when is_binary(html_url) <- get_pdf_template_url(order.order_nr, mode),
         filename when is_binary(filename) <- get_filename_for_order_nr(order.order_nr, mode),
         cloud_url when is_binary(cloud_url) <- generate_pdf_in_cloud(html_url, filename),
         {:ok, filename} when is_binary(filename) <- store_pdf_locally(cloud_url, filename) do
      filename
    end
  end

  def get_pdf_template_url(order_nr, mode, params \\ %{})
      when is_binary(order_nr) and is_binary(mode),
      do: @get_pdf_template_url.(order_nr, mode, params)

  def generate_pdf_in_cloud(html_url, filename)
      when is_binary(html_url) and is_binary(filename) do
    json = generate_json_options(%{url: html_url, fileName: filename})

    make_request(json)
    |> case do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> case do
          %{"pdf" => pdf} ->
            pdf

          res ->
            res |> Kandis.KdHelpers.log("api2pdf provided error-response ", :error)
        end

      res ->
        res |> Kandis.KdHelpers.log("api2pdf provided no response ", :error)
    end
  end

  def get_url_for_file(filename) do
    String.replace_leading(
      filename,
      Application.get_env(:kandis, :pdf_dir),
      Application.get_env(:kandis, :pdf_url)
    )
  end

  def store_pdf_locally(remote_pdf_url, filename) do
    {remote_pdf_url, filename}
    |> Kandis.KdHelpers.log(
      "store_pdf_locally(remote_pdf_url, filename) ",
      :info
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

  # def make_request(body) do
  #   base_url = Application.get_env(:kandis, :api2pdf)[:base_url]
  #   api_key = Application.get_env(:kandis, :api2pdf)[:api_key]

  #   HTTPoison.post(url, body, Authorization: api_key)
  # end

  def make_request(body) do
    base_url = "https://v2018.api2pdf.com"

    api_key = Application.get_env(:kandis, :api2pdf)[:api_key]

    url = "#{base_url}/chrome/url/"

    body
    |> Kandis.KdHelpers.log("calling pdf-cloud-service POST #{url} api-key:#{api_key}", :info)

    HTTPoison.post(url, body, [{"Authorization", api_key}],
      timeout: 60_000,
      recv_timeout: 60_000
    )
  end
end
