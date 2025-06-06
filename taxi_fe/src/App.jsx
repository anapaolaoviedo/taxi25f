import { useState } from 'react'
import './App.css'
import Customer from './components/Customer';
import Driver from './components/Driver';

function App() {
  return (
    <div className="App">
      <Customer username="Ana Paola"/>
      <Driver username="Travis"/>
      <Driver username="Drake"/>
      <Driver username="Kendrick"/>
    </div>
  )
}

export default App
