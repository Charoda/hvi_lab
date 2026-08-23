#!/bin/bash
# Stage 2 (FEAT-1731): Add job priority system.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding job priority system (FEAT-1731)..."

cat > src/services/jobQueue.js << 'JSEOF'
const crypto = require('crypto');

const MAX_WORKERS = 5;
let activeWorkers = 0;
const queue = [];
const jobs = new Map();

const PRIORITY_ORDER = { high: 0, normal: 1, low: 2 };

function createJob(type, payload, priority) {
  priority = priority || 'normal';
  if (!PRIORITY_ORDER.hasOwnProperty(priority)) priority = 'normal';
  const job = {
    id: crypto.randomUUID(),
    type,
    payload,
    priority,
    status: 'queued',
    createdAt: new Date().toISOString(),
    completedAt: null,
  };
  jobs.set(job.id, job);
  queue.push(job);
  queue.sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]);
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
  const byPriority = { high: 0, normal: 0, low: 0 };
  for (const job of jobs.values()) {
    byPriority[job.priority] = (byPriority[job.priority] || 0) + 1;
  }
  return {
    totalJobs: jobs.size,
    activeWorkers,
    queueDepth: queue.length,
    maxWorkers: MAX_WORKERS,
    byPriority,
  };
}

module.exports = { createJob, getJob, getStats };
JSEOF

cat > src/routes/v1/jobs.route.js << 'JSEOF'
const express = require('express');
const { createJob, getJob, getStats } = require('../../services/jobQueue');
const router = express.Router();

router.post('/', (req, res) => {
  const { type, payload, priority } = req.body;
  if (!type) return res.status(400).json({ error: 'type is required' });
  const job = createJob(type, payload || {}, priority || 'normal');
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

echo "  Updated job queue with priority system"
echo "Stage 2 complete."
