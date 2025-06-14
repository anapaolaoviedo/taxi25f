defmodule TaxiBeWeb.DriverChannel do
  use TaxiBeWeb, :channel

  def join("driver:" <> _username, _payload, socket) do
    {:ok, socket}
  end

  def handle_in("accept_ride", %{"booking_id" => booking_id}, socket) do
    # Simulación de ETA: 10 minutos desde ahora
    eta = DateTime.utc_now() |> DateTime.add(600, :second)

    driver_data = %{
      id: 1, # Reemplazar con datos reales del socket
      name: "Conductor de Prueba",
      eta: eta
    }

    case find_booking_process(booking_id) do
      pid when is_pid(pid) ->
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

  def handle_in("reject_ride", %{"booking_id" => booking_id}, socket) do
    driver_data = %{id: 1}

    case find_booking_process(booking_id) do
      pid when is_pid(pid) -> GenServer.call(pid, {:driver_rejected, driver_data})
      _ -> :ok
    end

    {:noreply, socket}
  end

  defp find_booking_process(booking_id) do
    case Registry.lookup(TaxiBe.ConcurrentBookingRegistry, booking_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
