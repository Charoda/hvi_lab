#!/bin/bash
# Stage 1: Add user registration with role management (FEAT-670)
# Uses in-memory store only — no external npm packages needed.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding user registration with role management (FEAT-670)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Rewrite index.js with user management (in-memory, no new deps)
cat > "$TARGET" << 'JSEOF'
const express = require('express');
const multer = require('multer');
const crypto = require('crypto');
const cors = require('cors');
const bodyParser = require('body-parser');
const morgan = require('morgan');

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';

// ---------- Role Hierarchy (FEAT-670) ----------

const ROLE_HIERARCHY = {
    viewer: 0,
    uploader: 1,
    editor: 2,
    admin: 3,
};

const DEFAULT_USER_ROLE = 'viewer';

// ---------- In-Memory User Store ----------

const users = {};
let userCounter = 0;

function hashPassword(password) {
    return crypto.createHash('sha256').update(password).digest('hex');
}

// ---------- Multer Setup ----------

const upload = multer({
    dest: `${FILE_PATH}/`,
    limits: {
        files: 5,
        fileSize: 2 * 1024 * 1024
    },
    fileFilter: (req, file, cb) => {
        if (!file.originalname.match(/\.(jpg|jpeg|png|gif)$/)) {
            return cb(new Error('Only images are allowed.'), false);
        }
        cb(null, true);
    }
});

// ---------- Middleware ----------

app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('dev'));

// ---------- Auth Endpoints (FEAT-670) ----------

// Register a new user
app.post('/auth/register', (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        const normalizedEmail = email.toLowerCase();
        const existing = Object.values(users).find(u => u.email === normalizedEmail);
        if (existing) {
            return res.status(409).json({ error: 'User already exists' });
        }

        userCounter++;
        const userId = `user_${userCounter}`;
        const user = {
            id: userId,
            email: normalizedEmail,
            password: hashPassword(password),
            role: DEFAULT_USER_ROLE,
            created_at: new Date().toISOString(),
        };
        users[userId] = user;

        res.status(201).json({
            user: {
                id: user.id,
                email: user.email,
                role: user.role,
            }
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Login
app.post('/auth/login', (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        const normalizedEmail = email.toLowerCase();
        const user = Object.values(users).find(u => u.email === normalizedEmail);
        if (!user || user.password !== hashPassword(password)) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        res.json({
            user: {
                id: user.id,
                email: user.email,
                role: user.role,
            }
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// List available roles
app.get('/roles', (req, res) => {
    const roles = Object.keys(ROLE_HIERARCHY).sort(
        (a, b) => ROLE_HIERARCHY[a] - ROLE_HIERARCHY[b]
    );
    res.json({
        roles,
        defaultRole: DEFAULT_USER_ROLE,
        hierarchy: ROLE_HIERARCHY,
    });
});

// ---------- Upload Endpoints ----------

app.post('/upload-avatar', upload.single('avatar'), (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).send({ status: false, data: 'No file is selected.' });
        }
        return res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                name: req.file.originalname,
                mimetype: req.file.mimetype,
                size: req.file.size
            }
        });
    } catch (err) {
        return res.status(500).send(err);
    }
});

app.post('/upload-photos', upload.array('photos', 8), (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).send({ status: false, data: 'No photo is selected.' });
        }
        const data = req.files.map((file) => ({
            name: file.originalname,
            mimetype: file.mimetype,
            size: file.size
        }));
        return res.send({ status: true, message: 'Photos are uploaded.', data });
    } catch (err) {
        return res.status(500).send(err);
    }
});

// ---------- Health ----------

app.get('/', (req, res) => {
    res.json({ status: 'ok', service: 'file-upload' });
});

const port = process.env.PORT || 3000;
app.listen(port, () =>
    console.log(`App is listening on port ${port}.`)
);
JSEOF

echo "  Rewrote $TARGET with in-memory user store and role hierarchy"
echo "Stage 1 complete."
