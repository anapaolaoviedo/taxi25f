import React from 'react';

function Driver({ username }) {
  return (
    <div className="card driver-card">
      <h4>Conductor: {username}</h4>
      <p>Estado: Disponible</p>
    </div>
  );
}

export default Driver;
