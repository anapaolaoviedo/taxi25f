defmodule TaxiBeWeb.CustomerChannel do
  use TaxiBeWeb, :channel

  alias TaxiBe.ConcurrentBookingProcess
  alias TaxiBe.Bookings

  def join("customer:" <> _username, _payload, socket) do
    {:ok, socket}
  end

  def handle_in("request_ride", payload, socket) do
    fake_booking = %{
      id: Ecto.UUID.generate(),
      origin: payload["origin"],
      destination: payload["destination"],
      status: "searching"
    }

    {:ok, _pid} = GenServer.start_link(
      ConcurrentBookingProcess,
      %{booking: fake_booking, customer_pid: self()},
      name: {:via, Registry, {TaxiBe.ConcurrentBookingRegistry, fake_booking.id}}
    )

    {:reply, {:ok, %{status: "Searching for a driver...", booking_id: fake_booking.id}}, socket}
  end

  def handle_in("cancel_ride", %{"booking_id" => booking_id}, socket) do
    case Registry.lookup(TaxiBe.ConcurrentBookingRegistry, booking_id) do
      [{pid, _}] ->
        response = GenServer.call(pid, :customer_cancelled)

        case response do
          :ok_no_charge ->
            push(socket, "ride_cancelled_successfully", %{status: "cancelled", charge: 0})
          :ok_charge_applied ->
            push(socket, "ride_cancelled_successfully", %{status: "cancelled", charge: 20})
        end

        # Detenemos el proceso de booking después de manejar la cancelación
        GenServer.stop(pid)
      _ ->
        :ok
    end
    {:noreply, socket}
  end

  def handle_info({:ride_accepted, data}, socket) do
    push(socket, "ride_accepted", data)
    {:noreply, socket}
  end

  def handle_info({:ride_not_fulfilled, data}, socket) do
    push(socket, "ride_not_fulfilled", data)
    {:noreply, socket}
  end
end
