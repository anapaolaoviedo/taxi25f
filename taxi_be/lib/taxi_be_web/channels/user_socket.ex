defmodule TaxiBeWeb.UserSocket do
  use Phoenix.Socket

  channel "customer:*", TaxiBeWeb.CustomerChannel
  channel "driver:*", TaxiBeWeb.DriverChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
