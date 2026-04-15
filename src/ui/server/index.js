'use strict';
require('express-async-errors');

const express = require('express');
const axios = require('axios');
const path = require('path');

// ── OpenTelemetry → Azure Monitor (App Insights) ─────────────────────────────
const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
if (connectionString) {
  const { useAzureMonitor } = require('@azure/monitor-opentelemetry');
  useAzureMonitor({ azureMonitorExporterOptions: { connectionString } });
}

const app = express();
app.use(express.json());

// ── Dapr service invocation helpers ──────────────────────────────────────────
const DAPR_HTTP_PORT = process.env.DAPR_HTTP_PORT || '3500';
const ORDER_SVC      = process.env.ORDER_SERVICE_APP_ID      || 'order-service';
const ACCOUNTING_SVC = process.env.ACCOUNTING_SERVICE_APP_ID || 'accounting-service';
const MAKELINE_SVC   = process.env.MAKELINE_SERVICE_APP_ID   || 'makeline-service';

const dapr = axios.create({ baseURL: `http://localhost:${DAPR_HTTP_PORT}` });

const svcUrl = (appId, path) => `/v1.0/invoke/${appId}/method${path}`;

// ── API routes (BFF proxying via Dapr service invocation) ────────────────────

// Place a new order
app.post('/api/orders', async (req, res) => {
  const { data } = await dapr.post(svcUrl(ORDER_SVC, '/api/orders'), req.body);
  res.status(202).json(data);
});

// Get a specific order
app.get('/api/orders/:orderId', async (req, res) => {
  const { data } = await dapr.get(svcUrl(ORDER_SVC, `/api/orders/${req.params.orderId}`));
  res.json(data);
});

// Get accounting metrics (for dashboard)
app.get('/api/accounting/metrics', async (req, res) => {
  const { data } = await dapr.get(svcUrl(ACCOUNTING_SVC, '/api/accounting/metrics'));
  res.json(data);
});

// Get makeline order queue (for dashboard)
app.get('/api/makeline/orders', async (req, res) => {
  const { data } = await dapr.get(svcUrl(MAKELINE_SVC, '/api/makeline/orders'));
  res.json(data);
});

// Mark order complete (makeline)
app.put('/api/makeline/orders/:orderId/complete', async (req, res) => {
  const { data } = await dapr.put(svcUrl(MAKELINE_SVC, `/api/makeline/orders/${req.params.orderId}/complete`));
  res.json(data);
});

// Health check
app.get('/healthz', (_, res) => res.json({ status: 'ok' }));

// ── Serve React SPA ───────────────────────────────────────────────────────────
const clientBuild = path.join(__dirname, '..', 'client', 'build');
app.use(express.static(clientBuild));

// Catch-all: serve React app for any non-API route (client-side routing)
app.get('*', (req, res) => {
  if (!req.path.startsWith('/api') && !req.path.startsWith('/healthz')) {
    res.sendFile(path.join(clientBuild, 'index.html'));
  } else {
    res.status(404).json({ error: 'Not found' });
  }
});

// Global error handler
app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.response?.status || 500).json({ error: err.message });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`UI BFF listening on port ${PORT}`));
