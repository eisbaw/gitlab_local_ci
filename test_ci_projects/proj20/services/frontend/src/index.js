// Frontend application entry point
import React from 'react';
import ReactDOM from 'react-dom/client';

const App = () => {
  return (
    <div>
      <h1>Monorepo Platform - Frontend</h1>
      <p>Version: 2.0.0</p>
    </div>
  );
};

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
