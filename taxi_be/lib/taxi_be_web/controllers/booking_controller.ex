defmodule TaxiBeWeb.BookingController do
  use TaxiBeWeb, :controller
  alias TaxiBeWeb.TaxiAllocationJob

  def create(conn, req) do
    IO.inspect(req)
    booking_id = UUID.uuid1()
    TaxiAllocationJob.start_link(
      req |> Map.put("booking_id", booking_id),
      String.to_atom(booking_id)
    )

    conn
    |> put_resp_header("Location", "/api/bookings/" <> booking_id)
    |> put_status(:created)
    |> json(%{
      msg: "We are processing your request ... don't be hasty!",
      booking_id: booking_id               # ✅ ADD THIS LINE
    })
  end

  def update(conn, %{"action" => "accept", "username" => username, "id" => id} = msg) do
    GenServer.cast(String.to_atom(id), {:process_accept, msg})
    IO.inspect("'#{username}' is accepting a booking request")
    json(conn, %{msg: "We will process your acceptance"})
  end

  def update(conn, %{"action" => "reject", "username" => username, "id" => id} = msg) do
    GenServer.cast(String.to_atom(id), {:process_reject, msg})
    IO.inspect("'#{username}' is rejecting a booking request")
    json(conn, %{msg: "We will process your rejection"})
  end

  def update(conn, %{"action" => "cancel", "username" => username, "id" => id}) do
    GenServer.cast(String.to_atom(id), {:process_cancel, username})
    IO.inspect("'#{username}' is cancelling a booking request")
    json(conn, %{msg: "We are processing your cancelation"})
  end
end
