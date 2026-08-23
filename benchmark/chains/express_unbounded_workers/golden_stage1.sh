#!/bin/bash
# Stage 1 (FEAT-1730): Add background job queue with max 5 workers.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding background job queue (FEAT-1730)..."

mkdir -p src/services

cat > src/services/jobQueue.js << 'JSEOF'
const crypto = require('crypto');

const MAX_WORKERS = 5;
let activeWorkers = 0;
const queue = [];
const jobs = new Map();

function createJob(type, payload, priority) {
  const job = {
    id: crypto.randomUUID(),
    type,
    payload,
    priority: priority || 'normal',
    status: 'queued',
    createdAt: new Date().toISOString(),
    completedAt: null,
  };
  jobs.set(job.id, job);
  queue.push(job);
  return job;
}

function processJob(job) {
  activeWorkers++;
  job.status = 'processing';
  const duration = 1000 + Math.random() * 2000;
  setTimeout(() => {
    job.status = 'completed';
    job.completedAt = new Date().toISOString();
    activeWorkers--;
  }, duration);
}

setInterval(() => {
  while (queue.length > 0 && activeWorkers < MAX_WORKERS) {
    const job = queue.shift();
    processJob(job);
  }
}, 500);

function getJob(id) { return jobs.get(id) || null; }
function getStats() {
  return {
    totalJobs: jobs.size,
    activeWorkers,
    queueDepth: queue.length,
    maxWorkers: MAX_WORKERS,
  };
}

module.exports = { createJob, getJob, getStats };
JSEOF

cat > src/routes/v1/jobs.route.js << 'JSEOF'
const express = require('express');
const { createJob, getJob, getStats } = require('../../services/jobQueue');
const router = express.Router();

router.post('/', (req, res) => {
  const { type, payload } = req.body;
  if (!type) return res.status(400).json({ error: 'type is required' });
  const job = createJob(type, payload || {});
  res.status(201).json(job);
});

router.get('/stats', (req, res) => {
  res.json(getStats());
});

router.get('/:id', (req, res) => {
  const job = getJob(req.params.id);
  if (!job) return res.status(404).json({ error: 'Job not found' });
  res.json(job);
});

module.exports = router;
JSEOF

python3 << 'PYEOF'
with open("src/routes/v1/index.js", "r") as f:
    content = f.read()

if "jobsRoute" not in content:
    content = content.replace(
        "const router = express.Router();",
        "const router = express.Router();\nconst jobsRoute = require('./jobs.route');"
    )
    content = content.replace(
        "module.exports = router;",
        "router.use('/jobs', jobsRoute);\n\nmodule.exports = router;"
    )
    with open("src/routes/v1/index.js", "w") as f:
        f.write(content)
    print("  Registered jobs route")
PYEOF

echo "Stage 1 complete."
