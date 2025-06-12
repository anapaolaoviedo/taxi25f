defmodule TaxiBeWeb.DriverChannel do
  use TaxiBeWeb, :channel

  @impl true
  def join("driver:" <> _username, _payload, socket) do
    {:ok, socket}
  end

  # El conductor acepta el viaje
  @impl true
  def handle_in("accept_ride", %{"booking_id" => booking_id}, socket) do
    driver_data = %{id: 1, name: "Conductor de Prueba"}


    pid = find_booking_process(booking_id)

    if pid do
      # Usamos `call` para esperar una respuesta síncrona
      case GenServer.call(pid, {:driver_accepted, driver_data}) do
        :ok ->
          # El conductor fue el primero, se le puede notificar en el front-end
          push(socket, "ride_confirmed", %{status: "you_got_it"})
        {:error, :already_taken} ->
          # Alguien más tomó el viaje
          push(socket, "ride_already_taken", %{status: "too_late"})
        _ -> :ok
      end
    end

    {:noreply, socket}
  end

  # El conductor rechaza el viaje
  @impl true
  def handle_in("reject_ride", %{"booking_id" => booking_id}, socket) do
    driver_data = %{id: 1, name: "Conductor de Prueba"}

    pid = find_booking_process(booking_id)
    if pid, do: GenServer.call(pid, {:driver_rejected, driver_data})

    {:noreply, socket}
  end

  defp find_booking_process(booking_id) do
    case Registry.lookup(TaxiBe.ConcurrentBookingRegistry, booking_id) do
      [{pid, _}] -> pid
      [] ->
        # Si no está en el concurrente, buscamos en el secuencial
        case Registry.lookup(TaxiBe.BookingRegistry, booking_id) do
          [{pid, _}] -> pid
          [] -> nil
        end
    end
  end
end
