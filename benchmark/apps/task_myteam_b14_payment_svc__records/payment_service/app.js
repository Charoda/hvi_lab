'use strict';

const express = require('express');

const app = express();
const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/payments', (_req, res) =>
  res.json([{ id: 'pay_1', amount: 1000, currency: 'USD' }])
);

if (require.main === module) {
  app.listen(PORT, HOST, () => {
    console.log(`Payment service listening on http://${HOST}:${PORT}`);
  });
}

module.exports = app;
