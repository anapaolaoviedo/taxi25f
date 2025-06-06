defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])          # Start step1 logic
    Process.send_after(self(), :timeout, 60_000)        # Trigger timeout in 1 min
    {:ok, %{request: request, status: :waiting}}        # Store request & state
  end

def compute_ride_fare(request) do
  %{
    "pickup_address" => pickup_address,
    "dropoff_address" => dropoff_address
   } = request

  # coord1 = TaxiBeWeb.Geolocator.geocode(pickup_address)
  # coord2 = TaxiBeWeb.Geolocator.geocode(dropoff_address)
  # {distance, _duration} = TaxiBeWeb.Geolocator.distance_and_duration(coord1, coord2)
  {request, [70,90,120,200,250] |> Enum.random() } # Float.ceil(distance/300)}
end

def notify_customer_ride_fare({request, fare}) do
  %{"username" => customer} = request
 TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{msg: "Ride fare: #{fare}"})
end

def find_candidate_taxis(%{"pickup_address" => _pickup_address}) do
  [
    %{nickname: "Travis", latitude: 19.0319783, longitude: -98.2349368},
    %{nickname: "Drake", latitude: 19.0061167, longitude: -98.2697737},
    %{nickname: "Kendrick", latitude: 19.0092933, longitude: -98.2473716}
  ]
end

  def handle_info(:step1, %{request: request} = state) do

    # task = Task.async(fn -> find_candidate_taxis(request) end)

    # compute_ride_fare(request)
    # |> notify_customer_ride_fare()

    # list_of_taxis = Task.await(task) |> Enum.shuffle()

    task = Task.async(fn ->
      compute_ride_fare(request)
      |> notify_customer_ride_fare()
    end)

    list_of_taxis = find_candidate_taxis(request)

    Task.await(task)

    IO.inspect(list_of_taxis)

    # # Select a taxi
    taxi = hd(list_of_taxis)

    # Forward request to taxi driver
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request
    TaxiBeWeb.Endpoint.broadcast(
      "driver:" <> taxi.nickname,
      "booking_request",
       %{
         msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
         bookingId: booking_id
        })

    timer = Process.send_after(self(), TimeOut, 2000)

    {:noreply, %{request: request, contacted_taxi: taxi, candidates: tl(list_of_taxis), timer: timer}}
  end

  def auxilary(%{request: request, candidates: list_of_taxis} = state) do
    taxi = hd(list_of_taxis)
    IO.inspect(taxi)
    # Forward request to taxi driver
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request
    TaxiBeWeb.Endpoint.broadcast(
      "driver:" <> taxi.nickname,
      "booking_request",
       %{
         msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
         bookingId: booking_id
        })

    {:noreply, %{state | contacted_taxi: taxi, candidates: tl(list_of_taxis)}}
  end


  def handle_info(TimeOut, state) do
    IO.puts("Time OUT!!!")
    auxilary(state)
  end

  def handle_cast({:process_reject, msg}, state) do
    IO.puts("ENTERED REJECTION")
    auxilary(state)
  end

  def handle_cast({:process_accept, msg}, state) do
    %{request: %{"username" => customer_username}} = state
    IO.puts("Inside handle_cast")
    IO.inspect(state)
    IO.puts("-------------------")
    IO.inspect(msg)
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer_username, "booking_request", %{msg: "Tu taxi esta en camino y llegara 5 minutos"})
    {:noreply, state}
  end

  def candidate_taxis() do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368}, # Angelopolis
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737}, # Arcangeles
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716} # Paseo Destino
    ]
  end
end
