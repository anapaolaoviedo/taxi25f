defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :parallel_step, [:nosuspend])
    {:ok, %{request: request, status: :waiting_parallel, candidates: [], timer: nil}}
  end

  def compute_ride_fare(request) do
    %{"pickup_address" => _, "dropoff_address" => _} = request
    {request, Enum.random([70, 90, 120, 200, 250])}
  end

  def notify_customer_ride_fare({request, fare}) do
    %{"username" => customer} = request
    IO.puts("📢 Notifying customer of fare: #{fare}")
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "Ride fare: #{fare}",
      bookingId: request["booking_id"] # send it early
    })
  end

  def find_candidate_taxis(_request) do
    [
      %{nickname: "Travis", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "Drake", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "Kendrick", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end

  def handle_info(:parallel_step, %{request: request} = state) do
    IO.puts("🚀 Starting parallel dispatch...")

    Task.start(fn ->
      compute_ride_fare(request)
      |> notify_customer_ride_fare()
    end)

    candidates = find_candidate_taxis(request) |> Enum.take(3)

    Enum.each(candidates, fn taxi ->
      %{"pickup_address" => pickup, "dropoff_address" => dropoff, "booking_id" => booking_id} = request

      IO.puts("📨 Sending request to driver #{taxi.nickname}")

      TaxiBeWeb.Endpoint.broadcast("driver:" <> taxi.nickname, "booking_request", %{
        msg: "Viaje de '#{pickup}' a '#{dropoff}'",
        bookingId: booking_id
      })
    end)

    timer = Process.send_after(self(), :no_driver_found, 90_000)
    IO.puts("⏱️ Timer set for 90s")

    {:noreply, %{state | candidates: candidates, timer: timer, status: :waiting_parallel}}
  end

  def handle_info(:no_driver_found, %{request: request, status: :waiting_parallel} = state) do
    %{"username" => customer} = request
    IO.puts("💥 No driver accepted after 1.5 min.")

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "🚫 No drivers available at the moment.",
      bookingId: request["booking_id"]
    })

    {:stop, :normal, state}
  end

  def handle_cast({:process_accept, msg}, %{request: request, timer: timer, candidates: candidates} = state) do
    if timer, do: Process.cancel_timer(timer)

    %{"username" => customer} = request
    now = DateTime.utc_now()
    eta = DateTime.add(now, 5 * 60, :second)

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "🚗 Tu taxi está en camino y llegará pronto.",
      bookingId: request["booking_id"]
    })

    Enum.each(candidates, fn driver ->
      unless driver.nickname == msg["username"] do
        IO.puts("🛑 Notifying #{driver.nickname} the ride was taken.")
        TaxiBeWeb.Endpoint.broadcast("driver:" <> driver.nickname, "booking_request", %{
          msg: "Otro conductor ha tomado el viaje. Esta solicitud ya no está disponible.",
          disable_buttons: true
        })
      end
    end)

    {:stop, :normal, %{
      state
      | status: :driver_found,
        driver_accepted_time: now,
        arrival_eta: eta
    }}
  end

  def handle_cast({:process_cancel, username}, state) do
    %{"username" => customer} = state.request

    cond do
      state.status == :waiting_parallel ->
        TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
          msg: "❌ Viaje cancelado sin cargo.",
          bookingId: state.request["booking_id"]
        })
        {:stop, :normal, state}

      state.status == :driver_found ->
        now = DateTime.utc_now()
        eta = state.arrival_eta || now
        mins_left = DateTime.diff(eta, now, :minute)

        if mins_left <= 3 do
          TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
            msg: "⚠️ Cancelación tardía. Se aplicará un cargo de $20.",
            bookingId: state.request["booking_id"]
          })
        else
          TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
            msg: "✅ Cancelado a tiempo. No se aplicará cargo.",
            bookingId: state.request["booking_id"]
          })
        end

        {:stop, :normal, state}

      true ->
        IO.puts("⚠️ Cancel in unexpected state: #{inspect(state.status)}")
        {:stop, :normal, state}
    end
  end

  def handle_cast({:process_reject, _msg}, state) do
    IO.puts("❌ Driver rejected the request.")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.puts("🪵 Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end
end
