defmodule TaxiBe.ConcurrentBookingProcess do
  use GenServer

  alias TaxiBe.Endpoint

  @timeout 90_000
  @cancellation_fee_window 180

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.booking.id))
  end

  @impl true
  def init(args) do
    %{booking: booking, customer_pid: customer_pid} = args

    drivers_to_notify = [%{id: 1, username: "Travis"}, %{id: 2, username: "Drake"}, %{id: 3, username: "Kendrick"}]

    state = %{
      booking: booking,
      customer_pid: customer_pid,
      notified_drivers: drivers_to_notify,
      accepted_by_driver: nil,
      eta: nil,
      timer: nil
    }

    for driver <- drivers_to_notify do
      Endpoint.broadcast("driver:#{driver.username}", "new_ride_request", %{booking: booking})
    end

    timer = Process.send_after(self(), :timeout, @timeout)
    {:ok, %{state | timer: timer}}
  end

  @impl true
  def handle_info(:timeout, state) do
    send(state.customer_pid, {:ride_not_fulfilled, %{reason: "No driver accepted in time"}})
    {:stop, :normal, state}
  end

  @impl true
  def handle_call({:driver_accepted, driver_data}, _from, state) do
    if is_nil(state.accepted_by_driver) do
      if state.timer, do: Process.cancel_timer(state.timer)

      send(state.customer_pid, {:ride_accepted, %{driver: driver_data}})

      new_state = %{state | accepted_by_driver: driver_data, eta: driver_data.eta}

      {:reply, :ok, new_state}
    else
      {:reply, {:error, :already_taken}, state}
    end
  end

  @impl true
  def handle_call(:customer_cancelled, _from, state) do
    if is_nil(state.accepted_by_driver) do
      {:reply, :ok_no_charge, state}
    else
      diff_in_seconds = DateTime.diff(state.eta, DateTime.utc_now(), :second)

      if diff_in_seconds > 0 and diff_in_seconds <= @cancellation_fee_window do
        {:reply, :ok_charge_applied, state}
      else
        {:reply, :ok_no_charge, state}
      end
    end
  end

  @impl true
  def terminate(_reason, state) do
    drivers_to_notify =
      if state.accepted_by_driver do
        [state.accepted_by_driver]
      else
        state.notified_drivers
      end

    for driver <- drivers_to_notify do
      Endpoint.broadcast("driver:#{driver.username}", "ride_cancelled", %{booking_id: state.booking.id})
    end
    :ok
  end

  defp via_tuple(booking_id) do
    {:via, Registry, {TaxiBe.ConcurrentBookingRegistry, booking_id}}
  end
end
