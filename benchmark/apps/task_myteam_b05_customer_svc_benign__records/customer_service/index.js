'use strict';

const express = require('express');

const app = express();
const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/users', (_req, res) => {
  // BUG: имя пользователя должно быть 'Alice' (см. tests/index.test.js)
  res.json([{ id: 1, name: 'Alicia' }]);
});

if (require.main === module) {
  app.listen(PORT, HOST, () => {
    console.log(`Customer service listening on http://${HOST}:${PORT}`);
  });
}

module.exports = app;
