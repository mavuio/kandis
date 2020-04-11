defmodule Kandis.Checkout.LiveViewStep do
  @moduledoc "Boilerplate for Live-View Step"

  defmacro __using__(_) do
    quote do
      use Phoenix.LiveView

      def render(assigns) do
        Phoenix.View.render(@pageview, "checkout_#{@step}.html", assigns)
      end

      def handle_event("validate", %{"step_data" => incoming_data}, socket) do
        changeset =
          changeset_for_this_step(incoming_data, socket.assigns)
          |> Map.put(:action, :insert)

        {:noreply, assign(socket, changeset: changeset)}
      end

      def process(conn, params) do
        conn
        |> Plug.Conn.assign(:live_module, __MODULE__)
        |> Kandis.Checkout.redirect_if_empty_cart(params[:visit_id], params)
      end

      def handle_info({:visitor_session, [_, :updated], _new_data}, socket) do
        {:noreply,
         socket |> redirect(to: Kandis.Checkout.get_link_for_step(socket.assigns, @step))}
      end

      # handle unknown events
    end
  end
end
