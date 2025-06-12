defmodule TaxiBe.BookingProcess do
  use GenServer
  require Logger

  alias TaxiBeWeb.DriverChannel
  alias TaxiBe.Bookings # Asumimos que tienes un contexto para la BD
  alias TaxiBe.Drivers # Asumimos que tienes un contexto para la BD

  @timeout 60_000 # 60 segundos en milisegundos

  # =================================================================
  # API Pública (lo que otros procesos pueden llamar)
  # =================================================================

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.booking.id))
  end

  # =================================================================
  # Callbacks del GenServer (lógica interna)
  # =================================================================

  @impl true
  def init(args) do
    # Extraemos los datos iniciales
    %{booking: booking, customer_pid: customer_pid} = args

    # Buscamos los conductores disponibles (esto es una suposición,
    # necesitas implementar esta lógica)
    drivers = Drivers.get_available_drivers(booking.origin)

    # Creamos el estado inicial del proceso
    state = %{
      booking: booking,
      customer_pid: customer_pid,
      available_drivers: drivers,
      current_driver: nil,
      timer: nil
    }

    Logger.info("Nuevo proceso de booking iniciado para el booking ##{booking.id}")

    # Inmediatamente intentamos notificar al primer conductor
    send(self(), :notify_next_driver)

    {:ok, state}
  end

  # --- Manejo de la lógica principal ---

  @impl true
  def handle_info(:notify_next_driver, state) do
    # Si teníamos un timer anterior, lo cancelamos.
    if state.timer, do: Process.cancel_timer(state.timer)

    case state.available_drivers do
      # Caso 1: Hay conductores en la lista
      [next_driver | remaining_drivers] ->
        Logger.info("Notificando al conductor #{next_driver.id} para el booking ##{state.booking.id}")

        # Enviamos la notificación al conductor a través de su canal
        TaxiBe.Endpoint.broadcast(
          "driver:#{next_driver.username}",
          "new_ride_request",
          %{booking: state.booking}
        )

        # Programamos un timeout de 60 segundos
        timer = Process.send_after(self(), :timeout, @timeout)

        new_state =
          state
          |> Map.put(:current_driver, next_driver)
          |> Map.put(:available_drivers, remaining_drivers)
          |> Map.put(:timer, timer)

        {:noreply, new_state}

      # Caso 2: No quedan conductores
      [] ->
        Logger.info("No se encontraron conductores para el booking ##{state.booking.id}")
        # Notificamos al cliente que no se encontró conductor
        send(state.customer_pid, {:ride_not_fulfilled, %{reason: "No drivers available"}})
        # Terminamos el proceso
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("Timeout para el conductor #{state.current_driver.id} en booking ##{state.booking.id}")
    # El conductor actual no respondió, intentamos con el siguiente
    send(self(), :notify_next_driver)
    {:noreply, %{state | timer: nil, current_driver: nil}}
  end


  # --- Manejo de respuestas del conductor ---

  @impl true
  def handle_cast({:driver_accepted, driver_data}, state) do
    Logger.info("El conductor #{driver_data.id} ACEPTÓ el booking ##{state.booking.id}")
    # Cancelamos el timer porque ya tenemos respuesta
    Process.cancel_timer(state.timer)

    # TODO: Actualizar el estado de la reserva en la base de datos
    # Bookings.update_booking(state.booking, status: "accepted", driver_id: driver_data.id)

    # Notificar al cliente que el viaje fue aceptado
    send(state.customer_pid, {:ride_accepted, %{driver: driver_data, booking: state.booking}})

    # Terminamos el proceso exitosamente
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:driver_rejected, _driver_data}, state) do
    Logger.info("El conductor #{state.current_driver.id} RECHAZÓ el booking ##{state.booking.id}")
    # Inmediatamente intentamos con el siguiente conductor, sin esperar el timeout
    send(self(), :notify_next_driver)
    {:noreply, %{state | timer: nil, current_driver: nil}}
  end


  # Función auxiliar para registrar el proceso
  defp via_tuple(booking_id) do
    {:via, Registry, {TaxiBe.BookingRegistry, booking_id}}
  end
end
