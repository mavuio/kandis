# via https://snippets.aktagon.com/snippets/776-pagination-with-phoenix-and-ecto
#
# see also https://gist.github.com/AlchemistCamp/f6bb3c3e1ef81612e6abebe6ae9f4988
defmodule Kandis.KdPagination do
  import Ecto.Query
  @repo Application.get_env(:kandis, :repo)

  #
  # ## Example
  #
  #    Snippets.Snippet
  #    |> order_by(desc: :inserted_at)
  #    |> Pagination.page(0, per_page: 10)
  #

  def page(query, page, per_page: per_page) when is_binary(page) do
    page = String.to_integer(page)
    page(query, page, per_page: per_page)
  end

  def page(query, page, per_page: per_page) when is_nil(page) or page == 0 do
    page(query, 1, per_page: per_page)
  end

  def page({results, total_count}, page, per_page: per_page)
      when is_list(results) and is_integer(total_count) do
    %{
      has_next: length(results) > per_page,
      has_prev: page > 1,
      prev_page: page - 1,
      page: page,
      next_page: page + 1,
      first: (page - 1) * per_page + 1,
      last: Enum.min([page * per_page, total_count]),
      count: total_count,
      list: Enum.slice(results, 0, per_page),
      per_page: per_page
    }
  end

  def page(query, page, per_page: per_page) do
    results = limit_query(query, page, per_page: per_page) |> @repo.all()
    total_count = @repo.one(from(t in subquery(query), select: count("*")))
    page({results, total_count}, page, per_page: per_page)
  end

  def limit_query(query, page, per_page: per_page) when is_binary(page) do
    limit_query(query, String.to_integer(page), per_page: per_page)
  end

  def limit_query(query, page, per_page: per_page) when is_nil(page) or page == 0 do
    limit_query(query, 1, per_page: per_page)
  end

  def limit_query(query, page, per_page: per_page) do
    query
    |> limit(^(per_page + 1))
    |> offset(^(per_page * (page - 1)))
  end
end
