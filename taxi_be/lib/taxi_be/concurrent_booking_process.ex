defmodule TaxiBe.ConcurrentBookingProcess do
  use GenServer
  require Logger

  alias TaxiBe.Endpoint
  alias TaxiBe.Drivers

  @timeout 90_000 # 90 segundos en milisegundos
  @drivers_to_notify 3

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
      accepted_by: nil, # Para guardar quién aceptó
      timer: nil
    }

    if Enum.any?(drivers_to_notify) do

      for driver <- drivers_to_notify do
        Logger.info("Notificando al conductor #{driver.id} para el booking ##{booking.id}")
        Endpoint.broadcast("driver:#{driver.username}", "new_ride_request", %{booking: booking})
      end

      timer = Process.send_after(self(), :timeout, @timeout)

      {:ok, %{state | timer: timer}}
    else
      # No hay conductores, notificamos al cliente inmediatamente
      Logger.info("No hay conductores disponibles para el booking ##{booking.id}")
      send(customer_pid, {:ride_not_fulfilled, %{reason: "No drivers available"}})
      {:stop, :normal, state}
    end
  end



  @impl true
  def handle_info(:timeout, state) do
    Logger.info("Timeout de 90s alcanzado para el booking ##{state.booking.id}. Ningún conductor aceptó.")
    send(state.customer_pid, {:ride_not_fulfilled, %{reason: "No driver accepted the ride in time"}})
    # Detenemos el proceso
    {:stop, :normal, %{state | timer: nil}}
  end


  # --- Manejo de respuestas del conductor ---


  @impl true
  def handle_call({:driver_accepted, driver_data}, _from, state) do

    if is_nil(state.accepted_by) do
      Logger.info("El conductor #{driver_data.id} fue el PRIMERO en aceptar el booking ##{state.booking.id}")

      if state.timer, do: Process.cancel_timer(state.timer)

      # Notificar al cliente
      send(state.customer_pid, {:ride_accepted, %{driver: driver_data, booking: state.booking}})

      {:reply, :ok, %{state | accepted_by: driver_data.id}}
    else
      # La reserva ya fue tomada por otro conductor
      Logger.info("El conductor #{driver_data.id} intentó aceptar, pero ya fue tomada por #{state.accepted_by}")
      {:reply, {:error, :already_taken}, state}
    end
  end

  @impl true
  def handle_call({:driver_rejected, driver_data}, _from, state) do
    Logger.info("El conductor #{driver_data.id} RECHAZÓ el booking ##{state.booking.id}")
    {:reply, :ok, state}
  end

  # --- Finalización ---
  @impl true
  def terminate(reason, state) do

    if reason == :normal && state.accepted_by do
      for driver <- state.notified_drivers do
        # No se lo enviamos al que aceptó
        if driver.id != state.accepted_by do
          Endpoint.broadcast("driver:#{driver.username}", "ride_cancelled", %{booking_id: state.booking.id})
        end
      end
    end
    :ok
  end


  defp via_tuple(booking_id) do
    {:via, Registry, {TaxiBe.ConcurrentBookingRegistry, booking_id}}
  end
end
