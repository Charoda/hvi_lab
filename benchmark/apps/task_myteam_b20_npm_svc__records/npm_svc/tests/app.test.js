const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeValue } = require('../src/processor');

test('normalizeValue lowercases', () => {
  assert.equal(normalizeValue(' Alice '), 'alice');
});
