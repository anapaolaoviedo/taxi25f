import React, { useEffect, useState } from 'react';
import Button from '@mui/material/Button';
import socket from '../services/taxi_socket';
import { TextField } from '@mui/material';

function Customer(props) {
  const [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  const [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  const [msg, setMsg] = useState("");
  const [msg1, setMsg1] = useState("");
  const [bookingId, setBookingId] = useState(null);
  const [hasActiveBooking, setHasActiveBooking] = useState(false);

  useEffect(() => {
    const channel = socket.channel("customer:" + props.username, { token: "123" });

    channel.on("booking_request", data => {
      console.log("📥 SOCKET MESSAGE:", data);
      setMsg1(data.msg);

      if (data.bookingId) {
        setBookingId(data.bookingId);
        setHasActiveBooking(true);
      }

      // If cancelled
      if (data.msg && data.msg.includes("cancelado")) {
        setBookingId(null);
        setHasActiveBooking(false);
      }
    });

    channel.join();

    return () => channel.leave();
  }, [props]);

  const submit = () => {
    fetch("http://localhost:4000/api/bookings", {
      method: "POST",
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pickup_address: pickupAddress,
        dropoff_address: dropOffAddress,
        username: props.username
      })
    })
    .then(resp => resp.json())
    .then(data => {
      console.log("🎉 Booking created:", data);
      setMsg(data.msg);
      if (data.booking_id) {
        setBookingId(data.booking_id);
        setHasActiveBooking(true);
      }
    });
  };

  const cancelRide = () => {
    if (!bookingId) return;

    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: "PUT",
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: "cancel",
        username: props.username
      })
    })
    .then(resp => resp.json())
    .then(data => {
      setMsg1(data.msg);
      setHasActiveBooking(false);
      setBookingId(null);
    });
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
          onClick={submit}
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
        {msg}
      </div>
      <div style={{ marginTop: "10px", background: "lightblue", padding: "10px" }}>
        {msg1}
      </div>
    </div>
  );
}

export default Customer;