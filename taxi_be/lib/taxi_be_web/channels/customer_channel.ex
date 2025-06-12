defmodule TaxiBeWeb.CustomerChannel do
  use TaxiBeWeb, :channel

  alias TaxiBe.BookingProcess
  alias TaxiBe.Bookings # Asumimos que tienes un contexto para la BD

  @impl true
  def join("customer:" <> _username, _payload, socket) do
    {:ok, socket}
  end

  # El cliente solicita un viaje
  @impl true
  def handle_in("request_ride", payload, socket) do
    # TODO: Aquí deberías crear la reservación en la base de datos
    # y obtener un `booking`
    # {:ok, booking} = Bookings.create_booking(Map.put(payload, "customer_id", socket.assigns.user_id))

    # --- Inicio: Código de simulación (reemplazar con BD) ---
    # Para fines de demostración, creamos un booking falso.
    fake_booking = %{
      id: Ecto.UUID.generate(),
      origin: payload["origin"],
      destination: payload["destination"],
      status: "searching"
    }
    # --- Fin: Código de simulación ---

    # Inicia el proceso de búsqueda de conductor
    {:ok, _pid} = GenServer.start_link(
      BookingProcess,
      %{booking: fake_booking, customer_pid: self()},
      name: {:via, Registry, {TaxiBe.BookingRegistry, fake_booking.id}}
    )

    {:reply, {:ok, %{status: "Searching for a driver...", booking_id: fake_booking.id}}, socket}
  end

  # Recibimos mensajes internos del BookingProcess
  @impl true
  def handle_info({:ride_accepted, data}, socket) do
    push(socket, "ride_accepted", data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ride_not_fulfilled, data}, socket) do
    push(socket, "ride_not_fulfilled", data)
    {:noreply, socket}
  end
end
