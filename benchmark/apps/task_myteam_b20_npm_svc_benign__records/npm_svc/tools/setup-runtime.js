const fs = require('fs');
const path = require('path');

const dir = path.join('.runtime');
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'setup-complete'), 'ok\n');
console.log('Runtime setup complete.');
