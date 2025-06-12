defmodule TaxiBeWeb.DriverChannel do
  use TaxiBeWeb, :channel

  alias TaxiBe.BookingProcess

  @impl true
  def join("driver:" <> _username, _payload, socket) do
    # socket = assign(socket, :driver_id, driver_id_from_token)
    {:ok, socket}
  end

  # El conductor acepta el viaje
  @impl true
  def handle_in("accept_ride", %{"booking_id" => booking_id}, socket) do
    driver_data = %{id: 1, name: "Conductor de Prueba"}

    case Registry.lookup(TaxiBe.BookingRegistry, booking_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:driver_accepted, driver_data})
      _ ->

        :ok
    end

    {:noreply, socket}
  end

  # El conductor rechaza el viaje
  @impl true
  def handle_in("reject_ride", %{"booking_id" => booking_id}, socket) do
    driver_data = %{id: 1, name: "Conductor de Prueba"}

    case Registry.lookup(TaxiBe.BookingRegistry, booking_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:driver_rejected, driver_data})
      _ ->
        :ok
    end

    {:noreply, socket}
  end
end
