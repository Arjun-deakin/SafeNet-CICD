const express = require('express');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3000;

// Prometheus metrics
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics();
const requestCounter = new client.Counter({
  name: 'safenet_requests_total',
  help: 'Total HTTP requests'
});

app.get('/health', (req, res) => {
  requestCounter.inc();
  res.json({ status: 'ok', service: 'safenet', time: new Date().toISOString() });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

// placeholder API for future
app.get('/api/ping', (req, res) => res.json({ pong: true }));

app.listen(PORT, () => console.log(`SafeNet API listening on ${PORT} - app.js:28`));

module.exports = app; // for tests
