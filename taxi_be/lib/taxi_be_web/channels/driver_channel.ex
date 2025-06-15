defmodule TaxiBeWeb.DriverChannel do
  use TaxiBeWeb, :channel

  @impl true
  def join("driver:" <> _username, _payload, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("accept_ride", %{"booking_id" => booking_id}, socket) do
    eta = DateTime.utc_now() |> DateTime.add(600, :second)

    driver_data = %{
      id: 1,
      name: "Conductor de Prueba",
      eta: eta
    }

    case Registry.lookup(TaxiBe.ConcurrentBookingRegistry, booking_id) do
      [{pid, _}] ->
        case GenServer.call(pid, {:driver_accepted, driver_data}) do
          :ok ->
            push(socket, "ride_confirmed", %{status: "you_got_it"})
          {:error, :already_taken} ->
            push(socket, "ride_already_taken", %{status: "too_late"})
        end
      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("reject_ride", %{"booking_id" => booking_id}, socket) do
    case Registry.lookup(TaxiBe.ConcurrentBookingRegistry, booking_id) do
      [{pid, _}] -> GenServer.cast(pid, {:driver_rejected, %{}})
      _ -> :ok
    end

    {:noreply, socket}
  end
end
