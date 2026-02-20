# Chicky Bites Biometric Attendance

A modern web-based attendance platform for **Chicky Bites** with:

- Secure admin authentication (session-based)
- Admin-only control panel
- Employee lifecycle management (add/update/delete)
- Attendance tracking (`present`, `absent`, `leave`)
- Leave request and approval workflow (admin-managed)
- Biometric attendance
  - Face recognition (enroll/verify/remove profile)
- Separate operational modes
  - `Attendance Mode` (kiosk-style daily operations)
  - `Biometric Management` (admin-only)

## Tech Stack

- Node.js + Express + EJS
- SQLite (`better-sqlite3`)
- Session auth (`express-session`)
- Client-side face detection (`face-api.js`)

## Setup

1. Install dependencies:

```bash
npm install
```

2. Configure environment:

```bash
cp .env.example .env
```

3. Start the app:

```bash
npm start
```

4. Open:

- `http://localhost:3000`

## Deploy on Render

This project includes `/render.yaml` for one-click Blueprint deployment.

### 1. Push project to GitHub

Render deploys from a Git repository.

```bash
git add .
git commit -m "Prepare Render deployment"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```

### 2. Create service from Blueprint

1. In Render Dashboard, click `New` -> `Blueprint`.
2. Connect your GitHub repo.
3. Render reads `render.yaml` and creates the web service with a persistent disk.

### 3. Set required environment variables

In Render service settings, define:

- `ADMIN_EMAIL` (your admin login email)
- `ADMIN_PASSWORD` (strong password)
- `KIOSK_PIN` (optional, for kiosk access)

Already configured by `render.yaml`:

- `NODE_ENV=production`
- `DB_PATH=/var/data/chickybites.db` (persistent SQLite path)
- `SESSION_SECRET` (auto-generated)

### 4. Deploy and open

After the first deploy completes, open your Render URL and sign in with the admin credentials set above.

## Default Admin Login

- Email: `admin@chickybites.com`
- Password: `ChangeMe@123`

Change this immediately in production.

## Biometric Notes

- **Face recognition**:
  - Uses browser camera + `face-api.js` descriptor extraction.
  - Requires decent lighting and front-facing image capture.

## Access Model

- Only `admin` can sign in.
- Optional `kiosk` attendance access via `KIOSK_PIN`.
- Employee records do not have web login accounts.
- Admin manages all employee data, including biometric and facial data.

## Production Hardening Checklist

- Use HTTPS and secure cookies (`secure: true`)
- Rotate `SESSION_SECRET`
- Add CSRF protection
- Add login rate limiting and account lockouts
- Add audit dashboard and immutable attendance logs
- Add encrypted biometric template storage and retention policy
- Replace local SQLite with managed DB for scale

## Project Structure

- `/server.js` - Routes, auth flow, and biometric API endpoints
- `/db.js` - SQLite schema and data access functions
- `/middleware/auth.js` - Auth + role middleware
- `/services/biometric.js` - Face descriptor normalization + matching helpers
- `/views` - EJS pages
- `/public` - CSS and browser-side biometric JS
- `/assets/logo.png` - Chicky Bites logo
