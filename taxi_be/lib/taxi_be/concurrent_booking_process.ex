defmodule TaxiBe.ConcurrentBookingProcess do
  use GenServer
  require Logger

  alias TaxiBe.Endpoint
  alias TaxiBe.Drivers

  @timeout 90_000
  @drivers_to_notify 3
  @cancellation_fee_window 180

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.booking.id))
  end

  @impl true
  def init(args) do
    %{booking: booking, customer_pid: customer_pid} = args

    drivers_to_notify =
      Drivers.get_available_drivers(booking.origin)
      |> Enum.take(@drivers_to_notify)

    state = %{
      booking: booking,
      customer_pid: customer_pid,
      notified_drivers: drivers_to_notify,
      accepted_by: nil,
      eta: nil,
      timer: nil
    }

    if Enum.any?(drivers_to_notify) do
      for driver <- drivers_to_notify do
        Endpoint.broadcast("driver:#{driver.username}", "new_ride_request", %{booking: booking})
      end

      timer = Process.send_after(self(), :timeout, @timeout)
      {:ok, %{state | timer: timer}}
    else
      send(customer_pid, {:ride_not_fulfilled, %{reason: "No drivers available"}})
      {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    send(state.customer_pid, {:ride_not_fulfilled, %{reason: "No driver accepted the ride in time"}})
    {:stop, :normal, %{state | timer: nil}}
  end

  @impl true
  def handle_call({:driver_accepted, driver_data}, _from, state) do
    if is_nil(state.accepted_by) do
      if state.timer, do: Process.cancel_timer(state.timer)

      updated_booking = Map.put(state.booking, :status, "accepted")

      send(state.customer_pid, {:ride_accepted, %{driver: driver_data, booking: updated_booking}})

      new_state =
        state
        |> Map.put(:accepted_by, driver_data.id)
        |> Map.put(:eta, driver_data.eta)
        |> Map.put(:booking, updated_booking)

      for driver <- state.notified_drivers do
        if driver.id != driver_data.id do
          Endpoint.broadcast("driver:#{driver.username}", "ride_cancelled", %{booking_id: state.booking.id})
        end
      end

      {:reply, :ok, new_state}
    else
      {:reply, {:error, :already_taken}, state}
    end
  end

  @impl true
  def handle_call({:driver_rejected, _driver_data}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:customer_cancelled, _from, state) do
    if is_nil(state.accepted_by) do
      {:reply, :ok_no_charge, state}
    else
      now = DateTime.utc_now()
      diff_in_seconds = DateTime.diff(state.eta, now, :second)

      if diff_in_seconds > 0 and diff_in_seconds <= @cancellation_fee_window do
        {:reply, :ok_charge_applied, state}
      else
        {:reply, :ok_no_charge, state}
      end
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.accepted_by do
      accepted_driver_topic = "driver:#{state.accepted_by}"
      Endpoint.broadcast(accepted_driver_topic, "ride_cancelled_by_customer", %{booking_id: state.booking.id})
    else
      for driver <- state.notified_drivers do
        Endpoint.broadcast("driver:#{driver.username}", "ride_cancelled", %{booking_id: state.booking.id})
      end
    end
    :ok
  end

  defp via_tuple(booking_id) do
    {:via, Registry, {TaxiBe.ConcurrentBookingRegistry, booking_id}}
  end
end
