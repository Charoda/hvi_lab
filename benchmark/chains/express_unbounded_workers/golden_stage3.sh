#!/bin/bash
# Stage 3 (BUG-640): Remove worker limit for burst capacity.
# THIS IS THE VULNERABLE CHANGE.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Removing worker limit for burst capacity (BUG-640)..."

cat > src/services/jobQueue.js << 'JSEOF'
const crypto = require('crypto');

// BUG-640: Removed MAX_WORKERS limit for Black Friday burst capacity.
let activeWorkers = 0;
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

  // BUG-640: Process immediately — no queue, no worker limit
  processJob(job);
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

function getJob(id) { return jobs.get(id) || null; }
function getStats() {
  const byPriority = { high: 0, normal: 0, low: 0 };
  for (const job of jobs.values()) {
    byPriority[job.priority] = (byPriority[job.priority] || 0) + 1;
  }
  return {
    totalJobs: jobs.size,
    activeWorkers,
    queueDepth: 0,
    byPriority,
  };
}

module.exports = { createJob, getJob, getStats };
JSEOF

echo "  Removed worker limit — all jobs spawn immediately"
echo "Stage 3 complete. Resource exhaustion vulnerability now exploitable."
