defmodule KandisTest do
  use ExUnit.Case

  # doctest KandisTest

  alias Kandis.Cart
  alias Kandis.VisitorSessionGenServer
  @userid1 "test_user1"

  setup do
    {:ok, server_pid} = VisitorSessionGenServer.start_link(@userid1)
    {:ok, server: server_pid}
  end

  def subset?(map1, map2) do
    keys = Map.keys(map1)

    map2
    |> Map.take(keys)
    |> Map.equal?(map1)
  end

  test "creates cart item int" do
    item = Cart.create_cart_item(0815, %{title: "product", subtitle: "in green"}, 2)
    assert item.amount == 2
    assert item.title == "product"
    assert item.sku == 815
  end

  test "creates cart item string" do
    item = Cart.create_cart_item("my_sku ", %{title: "product"})
    assert item.amount == 1
    assert item.title == "product"
    assert item.sku == "my_sku"
  end

  test "creates cart item nil sku" do
    item = Cart.create_cart_item(nil, "aaa")
    assert item == nil
  end

  test "creates cart item nil title" do
    item = Cart.create_cart_item("abc", nil)
    assert item == nil
  end

  test "get_empty_cart" do
    cart = Cart.get_cart_record(nil)
    assert cart.items == []
  end

  test "add to cart" do
    cart =
      Cart.get_empty_cart_record()
      |> Cart.add_item(0815, %{title: "Star Wars shirt"})

    firstitem =
      case cart do
        %{items: [item | _]} -> item
        _ -> nil
      end

    assert firstitem !== nil
    assert %{sku: 815, title: "Star Wars shirt", amount: 1} |> subset?(firstitem) == true
  end

  test "find in cart" do
    item =
      Cart.get_empty_cart_record()
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"})
      |> Cart.find_item("prod1")

    assert item !== nil
    assert %{sku: "prod1", title: "Star Wars shirt", amount: 1} |> subset?(item) == true
  end

  test "change quantity" do
    item =
      Cart.get_empty_cart_record()
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"}, 2)
      |> Cart.change_quantity("prod1", 10, "set")
      |> Cart.change_quantity("prod1", 5, "dec")
      |> Cart.change_quantity("prod1", 2, "inc")
      |> Cart.find_item("prod1")

    assert item.amount == 7
  end

  test "add 2 to cart" do
    cart =
      Cart.get_empty_cart_record()
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"})
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"}, 3)

    firstitem =
      case cart do
        %{items: [item | _]} -> item
        _ -> nil
      end

    assert firstitem !== nil
    assert %{sku: "prod1", title: "Star Wars shirt", amount: 4} |> subset?(firstitem) == true
  end

  test "remove from cart" do
    cart =
      Cart.get_empty_cart_record()
      |> Cart.add_item("prod2", %{title: "Tomato soup"}, 3)
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"})
      |> Cart.remove_item("prod2")

    firstitem =
      case cart do
        %{items: [item | _]} -> item
        _ -> nil
      end

    assert firstitem !== nil
    assert firstitem.sku == "prod1"
  end

  test "cart count" do
    count =
      Cart.get_empty_cart_record()
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"})
      |> Cart.add_item("prod1", %{title: "Star Wars shirt"}, 3)
      |> Cart.get_cart_count()

    assert count == 4
  end

  test "add promocode" do
    count =
      Cart.get_empty_cart_record()
      |> Cart.add_promocode("code1")
      |> Cart.add_promocode("code2")
      |> Cart.add_promocode("code1")
      |> Cart.get_promocodes()
      |> Enum.count()

    assert count == 2
  end

  test "remove promocode" do
    count =
      Cart.get_empty_cart_record()
      |> Cart.add_promocode("code1")
      |> Cart.add_promocode("code2")
      |> Cart.remove_promocode("code1")
      |> Cart.get_promocodes()
      |> Enum.count()

    assert count == 1
  end
end
