defmodule Kandis.Pdfgenerator do
  alias Kandis.Order
  import Kandis.KdHelpers, warn: false
  @moduledoc false

  @get_pdf_template_url Application.get_env(:kandis, :get_pdf_template_url)

  # deprecated in 0.4.5
  # def get_pdf_file_for_invoice_nr(invoice_nr, mode, params \\ %{}) when is_binary(mode) do
  #   filename = get_filename_for_invoice_nr(invoice_nr, mode)

  #   case File.exists?(filename) and is_nil(params["regenerate"]) do
  #     true ->
  #       filename

  #     false ->
  #       generated_filename = generate_invoice_pdf(mode, invoice_nr)

  #       if generated_filename == filename do
  #         filename
  #       else
  #         raise "filenames do not match #{generated_filename} vs #{filename}"
  #       end
  #   end
  # end
  #
  # def get_filename_for_invoice_nr(invoice_nr, mode)
  #     when is_binary(invoice_nr) and is_binary(mode) do
  #   pdf_dir = Application.get_env(:kandis, :pdf_dir)
  #   filename = "#{mode}_#{invoice_nr}.pdf"
  #   "#{pdf_dir}/#{filename}"
  # end

  def get_pdf_file_for_order_nr(order_nr, version, mode, params \\ %{})
      when is_integer(version) and is_binary(mode) do
    filename = get_filename_for_order_nr(order_nr, version, mode)

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

  def get_filename_for_order_nr(order_nr, version, mode)
      when is_integer(version) and is_binary(order_nr) and
             is_binary(mode) do
    pdf_dir = Application.get_env(:kandis, :pdf_dir)

    version_addon =
      case version do
        1 -> ""
        v -> "_#{v}"
      end

    filename = "#{order_nr}#{version_addon}_#{mode}.pdf"
    "#{pdf_dir}/#{filename}"
  end

  def get_all_files_for_order_nr(order_nr) when is_binary(order_nr) do
    pdf_dir = Application.get_env(:kandis, :pdf_dir)

    Path.wildcard("#{pdf_dir}/#{order_nr}*.*")
    |> Enum.map(&get_fileinfo/1)
    |> Enum.filter(fn a -> a[:version] end)
    |> Enum.sort_by(& &1.version)
  end

  def get_fileinfo(path) do
    File.stat(path)
    |> case do
      {:ok, stat} ->
        %{
          created_at: stat.ctime |> NaiveDateTime.from_erl!(),
          size: stat.size
        }

      _ ->
        %{}
    end
    |> Map.merge(parse_filename(path))
  end

  def parse_filename(path) when is_binary(path) do
    filename = Path.basename(path)

    {_ordernr, version, mode, extension} =
      case String.split(filename, ~w( _ . )) do
        [ordernr, mode, "pdf" = ext] ->
          {ordernr, 1, mode, ext}

        [ordernr, version, mode, "pdf" = ext] ->
          {ordernr, version |> to_int(), mode, ext}

        _ ->
          {nil, nil, nil, nil}
      end

    %{
      url: get_url_for_file(path),
      filename: filename,
      mode: mode,
      version: version,
      ext: extension
    }
  end

  @spec generate_invoice_pdf(
          binary,
          binary | integer | %{:__struct__ => atom, optional(any) => any}
        ) :: any
  def generate_invoice_pdf(mode, any_order_id) when is_binary(mode) do
    any_order_id |> Kandis.KdHelpers.log("generate_invoice_pdf #{mode}", :info)

    with order when is_map(order) <- Order.get_by_any_id(any_order_id),
         html_url when is_binary(html_url) <- get_pdf_template_url(order.order_nr, mode),
         filename when is_binary(filename) <-
           get_filename_for_order_nr(order.order_nr, order.version, mode),
         cloud_url when is_binary(cloud_url) <- generate_pdf_in_cloud(html_url, filename),
         {:ok, filename} when is_binary(filename) <- store_pdf_locally(cloud_url, filename) do
      filename
    end
  end

  def generate_order_pdf(mode, any_order_id) when is_binary(mode) do
    any_order_id |> Kandis.KdHelpers.log("generate_order_pdf #{mode}", :info)

    if Application.get_env(:kandis, :api2pdf)[:simulate_pdf] do
      simulate_order_pdf(mode, any_order_id)
    else
      with order when is_map(order) <- Order.get_by_any_id(any_order_id),
           html_url when is_binary(html_url) <- get_pdf_template_url(order.order_nr, mode),
           filename when is_binary(filename) <-
             get_filename_for_order_nr(order.order_nr, order.version, mode),
           cloud_url when is_binary(cloud_url) <- generate_pdf_in_cloud(html_url, filename),
           {:ok, filename} when is_binary(filename) <- store_pdf_locally(cloud_url, filename) do
        filename
      end
    end
  end

  def simulate_order_pdf(mode, any_order_id) when is_binary(mode) do
    any_order_id |> Kandis.KdHelpers.log("generate_order_pdf #{mode}", :info)

    with order when is_map(order) <- Order.get_by_any_id(any_order_id),
         html_url when is_binary(html_url) <- get_pdf_template_url(order.order_nr, mode),
         filename when is_binary(filename) <-
           get_filename_for_order_nr(order.order_nr, order.version, mode),
         {:ok, filename} when is_binary(filename) <- create_fake_file(html_url, filename) do
      filename
    end
  end

  def create_fake_file(url, filename) do
    if File.exists?(filename) do
      :ok = File.rm(filename)
    end

    # {url,filename}|>IO.inspect(label: "mwuits-debug 2021-03-04_11:24 ")
    # Download.from(url, path: filename)
    File.write(filename, "url: #{url}")
    |> case do
      :ok -> {:ok, filename}
      a -> a
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
