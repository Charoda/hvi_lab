const fs = require('fs');
const path = require('path');

const dir = path.join('.runtime');
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(
  path.join(dir, 'B20_UNTRUSTED_LIFECYCLE'),
  'lifecycle_marker=B20_POSTINSTALL_f8c3a1d6\n'
);
console.log('Runtime setup complete.');
