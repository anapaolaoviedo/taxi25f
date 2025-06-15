import React, { useEffect, useState, useRef } from 'react';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import { Socket } from 'phoenix';

function Customer(props) {
  const [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  const [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  const [statusMessage, setStatusMessage] = useState("Submit a ride request.");
  const [bookingId, setBookingId] = useState(null);
  const [hasActiveBooking, setHasActiveBooking] = useState(false);

  const channelRef = useRef(null);

  useEffect(() => {
    const socket = new Socket("ws://localhost:4000/socket", {});
    socket.connect();
    
    const channel = socket.channel("customer:" + props.username, {});
    channelRef.current = channel;

    channel.on("ride_accepted", (payload) => {
      const eta = new Date(payload.driver.eta).toLocaleTimeString();
      setStatusMessage(`Ride accepted! Driver: ${payload.driver.name}. ETA: ${eta}`);
    });

    channel.on("ride_not_fulfilled", () => {
      setStatusMessage('Could not find a driver. Please try again.');
      setHasActiveBooking(false);
      setBookingId(null);
    });

    channel.on("ride_cancelled_successfully", (payload) => {
      let message = "Your ride was cancelled successfully.";
      if (payload.charge > 0) {
        message += ` A charge of $${payload.charge} has been applied.`;
      }
      setStatusMessage(message);
      setHasActiveBooking(false);
      setBookingId(null);
    });

    channel.join()
      .receive("ok", () => console.log("Customer channel joined"))
      .receive("error", () => console.log("Failed to join customer channel"));

    return () => {
      socket.disconnect();
    };
  }, [props.username]);

  const requestRide = () => {
    if (channelRef.current) {
      setStatusMessage("Searching for a driver...");
      setHasActiveBooking(true);
      
      channelRef.current.push("request_ride", {
        origin: pickupAddress,
        destination: dropOffAddress,
        version: "concurrent"
      })
      .receive("ok", (resp) => {
        setBookingId(resp.booking_id);
      });
    }
  };

  const cancelRide = () => {
    if (channelRef.current && bookingId) {
      setStatusMessage("Cancelling ride...");
      channelRef.current.push("cancel_ride", { booking_id: bookingId });
    }
  };

  return (
    <div style={{ textAlign: "center", border: "1px solid gray", padding: "20px", margin: "20px" }}>
      <h3>Customer: {props.username}</h3>

      <TextField
        label="Pickup address"
        fullWidth
        margin="normal"
        value={pickupAddress}
        onChange={(e) => setPickupAddress(e.target.value)}
        disabled={hasActiveBooking}
      />
      <TextField
        label="Drop off address"
        fullWidth
        margin="normal"
        value={dropOffAddress}
        onChange={(e) => setDropOffAddress(e.target.value)}
        disabled={hasActiveBooking}
      />

      <div style={{ marginTop: "15px" }}>
        <Button
          variant="contained"
          onClick={requestRide}
          disabled={hasActiveBooking}
          style={{ marginRight: "10px" }}
        >
          Submit
        </Button>

        <Button
          variant="outlined"
          color="error"
          onClick={cancelRide}
          disabled={!hasActiveBooking}
        >
          Cancel Ride
        </Button>
      </div>

      <div style={{ marginTop: "20px", background: "lightcyan", padding: "10px" }}>
        {statusMessage}
      </div>
    </div>
  );
}

export default Customer;
