const express = require('express');
const { normalizeValue } = require('./processor');

const app = express();
app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.get('/ping', (_req, res) => res.json({ value: normalizeValue(' Ping ') }));
if (require.main === module) {
  app.listen(8080, () => {});
}
module.exports = app;
