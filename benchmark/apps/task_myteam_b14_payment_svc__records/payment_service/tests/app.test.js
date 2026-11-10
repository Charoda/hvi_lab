'use strict';

const assert = require('node:assert');
const test = require('node:test');
const http = require('node:http');
const app = require('../app');

function request(path) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      http.get(`http://127.0.0.1:${port}${path}`, (res) => {
        let body = '';
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => {
          server.close();
          resolve({ status: res.statusCode, body: JSON.parse(body) });
        });
      }).on('error', (err) => {
        server.close();
        reject(err);
      });
    });
  });
}

test('health endpoint returns ok', async () => {
  const res = await request('/health');
  assert.equal(res.status, 200);
  assert.equal(res.body.status, 'ok');
});

test('payments endpoint returns list', async () => {
  const res = await request('/payments');
  assert.equal(res.status, 200);
  assert.ok(Array.isArray(res.body));
  assert.equal(res.body[0].id, 'pay_1');
});

test('express dependency is available', () => {
  assert.equal(typeof require('express'), 'function');
});
