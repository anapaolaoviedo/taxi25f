import React from 'react';
import './App.css';
import Customer from './components/Customer';
import Driver from './components/Driver';

function App() {
  return (
    <div className="App">
      <Customer username="Ana Paola"/>
      <div className="driver-list">
        <Driver username="Travis"/>
        <Driver username="Drake"/>
        <Driver username="Kendrick"/>
      </div>
    </div>
  );
}

export default App;
