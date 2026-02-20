import bcrypt from 'bcryptjs';
import express from 'express';
import session from 'express-session';
import helmet from 'helmet';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import db, {
  addBiometricLog,
  createEmployee,
  createLeaveRequest,
  deleteEmployee,
  deleteFaceProfile,
  findUserByEmail,
  getBiometricMetrics,
  getDashboardStats,
  getEmployeeBiometricSummary,
  getEmployeeById,
  getFaceProfile,
  isValidAttendanceStatus,
  listAttendanceForDate,
  listBiometricLogs,
  listEmployees,
  listFaceProfilesForMatching,
  listLeaveRecords,
  listTodayAttendanceLog,
  storeFaceProfile,
  updateEmployee,
  updateLeaveStatus,
  upsertAttendance,
} from './db.js';
import { attachCurrentUser, requireAuth, requireKioskOrAdmin, requireRoles } from './middleware/auth.js';
import { isFaceMatch, normalizeDescriptor } from './services/biometric.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(import.meta.url);
const SQLiteStore = require('better-sqlite3-session-store')(session);

const app = express();
const PORT = Number(process.env.PORT || 3000);
const ORIGIN = process.env.RP_ORIGIN || `http://localhost:${PORT}`;
const KIOSK_PIN = process.env.KIOSK_PIN || '2468';
const IS_PROD = process.env.NODE_ENV === 'production';
const ISO_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const DMY_DATE_RE = /^(\d{2})-{1,2}(\d{2})-{1,2}(\d{4})$/;
const SQL_DATETIME_RE = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$/;

const pad2 = (value) => String(value).padStart(2, '0');
const isoToday = () => new Date().toISOString().slice(0, 10);

const isValidDateParts = (year, month, day) => {
  const candidate = new Date(Date.UTC(year, month - 1, day));
  return (
    candidate.getUTCFullYear() === year &&
    candidate.getUTCMonth() + 1 === month &&
    candidate.getUTCDate() === day
  );
};

const parseDateToIso = (value) => {
  if (value == null) {
    return null;
  }

  const raw = String(value).trim();
  if (!raw) {
    return null;
  }

  const isoMatch = raw.match(ISO_DATE_RE);
  if (isoMatch) {
    const year = Number(isoMatch[1]);
    const month = Number(isoMatch[2]);
    const day = Number(isoMatch[3]);
    if (!isValidDateParts(year, month, day)) {
      return null;
    }
    return `${year}-${pad2(month)}-${pad2(day)}`;
  }

  const dmyMatch = raw.match(DMY_DATE_RE);
  if (!dmyMatch) {
    return null;
  }

  const day = Number(dmyMatch[1]);
  const month = Number(dmyMatch[2]);
  const year = Number(dmyMatch[3]);
  if (!isValidDateParts(year, month, day)) {
    return null;
  }

  return `${year}-${pad2(month)}-${pad2(day)}`;
};

const formatDate = (value) => {
  const iso = parseDateToIso(value);
  if (!iso) {
    return value || '-';
  }

  const [year, month, day] = iso.split('-');
  return `${day}-${month}-${year}`;
};

const formatDateTime = (value) => {
  if (!value) {
    return '-';
  }

  const raw = String(value).trim();
  const parts = raw.match(SQL_DATETIME_RE);
  if (parts) {
    const [, year, month, day, hour = '00', minute = '00'] = parts;
    return `${day}-${month}-${year} ${hour}:${minute}`;
  }

  return formatDate(raw);
};

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", 'https://cdn.jsdelivr.net'],
        styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
        fontSrc: ["'self'", 'https://fonts.gstatic.com', 'data:'],
        imgSrc: ["'self'", 'data:', 'blob:'],
        connectSrc: ["'self'", 'https://cdn.jsdelivr.net'],
        mediaSrc: ["'self'", 'blob:'],
      },
    },
  })
);

app.use(express.urlencoded({ extended: true }));
app.use(express.json({ limit: '3mb' }));

if (IS_PROD) {
  // Render terminates TLS at the proxy, so trust X-Forwarded-* for secure cookies.
  app.set('trust proxy', 1);
}

const sessionStore = new SQLiteStore({
  client: db,
  expired: {
    clear: true,
    intervalMs: 15 * 60 * 1000,
  },
});

app.use(
  session({
    name: 'cb_attendance_sid',
    secret: process.env.SESSION_SECRET || 'cb_attendance_please_change_me',
    resave: false,
    saveUninitialized: false,
    proxy: IS_PROD,
    store: sessionStore,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: IS_PROD,
      maxAge: 1000 * 60 * 60 * 10,
    },
  })
);

app.use('/assets', express.static(path.join(__dirname, 'assets')));
app.use('/public', express.static(path.join(__dirname, 'public')));
app.use(attachCurrentUser);

app.use((req, res, next) => {
  const flash = req.session.flash || null;
  req.session.flash = null;
  const todayIso = isoToday();

  res.locals.currentUser = req.currentUser || null;
  res.locals.isKiosk = Boolean(req.session.isKiosk);
  res.locals.flash = flash;
  res.locals.today = formatDate(todayIso);
  res.locals.todayIso = todayIso;
  res.locals.formatDate = formatDate;
  res.locals.formatDateTime = formatDateTime;

  next();
});

const setFlash = (req, message, type = 'info') => {
  req.session.flash = { type, message };
};

const parseDateIn = (value, fallback) => {
  if (!value) {
    return fallback;
  }

  const safe = parseDateToIso(value);
  return safe || fallback;
};

const dateRange = (startDate, endDate) => {
  const start = new Date(`${startDate}T00:00:00Z`);
  const end = new Date(`${endDate}T00:00:00Z`);

  const out = [];
  for (let d = start; d <= end; d = new Date(d.getTime() + 24 * 60 * 60 * 1000)) {
    out.push(d.toISOString().slice(0, 10));
  }

  return out;
};

const actorUserId = (req) => req.currentUser?.id || null;

app.get('/', (req, res) => {
  if (req.currentUser?.role === 'admin' || req.session.isKiosk) {
    return res.redirect('/attendance-mode');
  }

  return res.redirect('/login');
});

app.get('/login', (req, res) => {
  if (req.currentUser?.role === 'admin') {
    return res.redirect('/dashboard');
  }

  return res.render('login', { pageTitle: 'Admin Sign In' });
});

app.post('/login', (req, res) => {
  const schema = z.object({
    email: z.string().trim().email(),
    password: z.string().min(1),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    setFlash(req, 'Invalid email or password format.', 'error');
    return res.redirect('/login');
  }

  const { email, password } = parsed.data;
  const user = findUserByEmail(email);

  if (!user || user.role !== 'admin') {
    setFlash(req, 'Only admin can access this application.', 'error');
    return res.redirect('/login');
  }

  const valid = bcrypt.compareSync(password, user.password_hash);
  if (!valid) {
    setFlash(req, 'Invalid credentials.', 'error');
    return res.redirect('/login');
  }

  req.session.userId = user.id;
  req.session.isKiosk = false;
  setFlash(req, `Welcome back, ${user.full_name}.`, 'success');
  return res.redirect('/dashboard');
});

app.get('/kiosk-login', (req, res) => {
  if (req.currentUser?.role === 'admin' || req.session.isKiosk) {
    return res.redirect('/attendance-mode');
  }

  return res.render('kiosk-login', { pageTitle: 'Kiosk Access' });
});

app.post('/kiosk-login', (req, res) => {
  const schema = z.object({ pin: z.string().trim().min(1) });
  const parsed = schema.safeParse(req.body);

  if (!parsed.success || parsed.data.pin !== KIOSK_PIN) {
    setFlash(req, 'Invalid kiosk PIN.', 'error');
    return res.redirect('/kiosk-login');
  }

  req.session.userId = null;
  req.session.isKiosk = true;
  setFlash(req, 'Kiosk mode activated.', 'success');
  return res.redirect('/attendance-mode');
});

app.post('/logout', (req, res) => {
  req.session.destroy(() => {
    res.redirect('/login');
  });
});

app.post('/kiosk-logout', (req, res) => {
  req.session.isKiosk = false;
  return res.redirect('/kiosk-login');
});

app.get('/dashboard', requireRoles('admin'), (req, res) => {
  const stats = getDashboardStats();
  const employees = listEmployees().slice(0, 8);
  const metrics = getBiometricMetrics();

  return res.render('dashboard', {
    pageTitle: 'Dashboard',
    stats,
    metrics,
    employees,
  });
});

app.get('/attendance-mode', requireKioskOrAdmin, (req, res) => {
  const today = isoToday();

  return res.render('attendance-mode', {
    pageTitle: 'Attendance Mode',
    kioskMode: Boolean(req.session.isKiosk),
    lockedDate: formatDate(today),
  });
});

app.get('/employees', requireRoles('admin'), (req, res) => {
  const employees = listEmployees();
  const editId = req.query.edit;
  const editingEmployee = editId ? getEmployeeById(editId) : null;

  if (editId && !editingEmployee) {
    setFlash(req, 'Employee not found for editing.', 'error');
    return res.redirect('/employees');
  }

  return res.render('employees', {
    pageTitle: 'Employees',
    employees,
    editingEmployee,
  });
});

app.post('/employees', requireRoles('admin'), (req, res) => {
  const schema = z.object({
    employeeCode: z.string().trim().min(2).max(32),
    fullName: z.string().trim().min(2).max(120),
    phone: z.string().trim().max(30).optional().or(z.literal('')),
    position: z.string().trim().max(80).optional().or(z.literal('')),
    role: z.enum(['manager', 'staff']),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    setFlash(req, 'Please check employee form fields.', 'error');
    return res.redirect('/employees');
  }

  try {
    const payload = parsed.data;
    createEmployee({
      employeeCode: payload.employeeCode,
      fullName: payload.fullName,
      phone: payload.phone,
      position: payload.position,
      role: payload.role,
    });

    setFlash(req, `Employee ${payload.fullName} was added.`, 'success');
    return res.redirect('/employees');
  } catch (error) {
    setFlash(req, error.message.includes('UNIQUE') ? 'Employee code already exists.' : error.message, 'error');
    return res.redirect('/employees');
  }
});

app.post('/employees/:id/update', requireRoles('admin'), (req, res) => {
  const employeeId = req.params.id;
  const employee = getEmployeeById(employeeId);

  if (!employee) {
    setFlash(req, 'Employee not found.', 'error');
    return res.redirect('/employees');
  }

  const schema = z.object({
    employeeCode: z.string().trim().min(2).max(32),
    fullName: z.string().trim().min(2).max(120),
    phone: z.string().trim().max(30).optional().or(z.literal('')),
    position: z.string().trim().max(80).optional().or(z.literal('')),
    role: z.enum(['manager', 'staff']),
    status: z.enum(['active', 'inactive']),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    setFlash(req, 'Invalid employee update payload.', 'error');
    return res.redirect(`/employees?edit=${encodeURIComponent(employeeId)}`);
  }

  try {
    const payload = parsed.data;
    updateEmployee({
      employeeId,
      employeeCode: payload.employeeCode,
      fullName: payload.fullName,
      phone: payload.phone,
      position: payload.position,
      role: payload.role,
      status: payload.status,
    });

    setFlash(req, `${payload.fullName} updated successfully.`, 'success');
    return res.redirect('/employees');
  } catch (error) {
    setFlash(req, error.message.includes('UNIQUE') ? 'Employee code already exists.' : error.message, 'error');
    return res.redirect(`/employees?edit=${encodeURIComponent(employeeId)}`);
  }
});

app.post('/employees/:id/delete', requireRoles('admin'), (req, res) => {
  const employeeId = req.params.id;
  const employee = getEmployeeById(employeeId);

  if (!employee) {
    setFlash(req, 'Employee not found.', 'error');
    return res.redirect('/employees');
  }

  deleteEmployee(employeeId);
  setFlash(req, `${employee.full_name} and associated records were deleted.`, 'success');
  return res.redirect('/employees');
});

app.get('/attendance', requireRoles('admin'), (req, res) => {
  const date = parseDateIn(req.query.date, isoToday());
  const rows = listAttendanceForDate(date);

  return res.render('attendance', {
    pageTitle: 'Attendance Records',
    date,
    rows,
    canManage: true,
  });
});

app.post('/attendance/mark', requireRoles('admin'), (req, res) => {
  const schema = z.object({
    employeeId: z.string().uuid(),
    date: z.string().trim().min(1),
    status: z.string(),
    notes: z.string().max(250).optional().or(z.literal('')),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    setFlash(req, 'Invalid attendance form submission.', 'error');
    return res.redirect('/attendance');
  }

  const { employeeId, date, status, notes } = parsed.data;
  const safeDate = parseDateIn(date, null);

  if (!safeDate) {
    setFlash(req, 'Invalid date format. Use dd-mm-yyyy.', 'error');
    return res.redirect('/attendance');
  }

  if (!isValidAttendanceStatus(status)) {
    setFlash(req, 'Invalid attendance status.', 'error');
    return res.redirect(`/attendance?date=${encodeURIComponent(formatDate(safeDate))}`);
  }

  const employee = getEmployeeById(employeeId);
  if (!employee) {
    setFlash(req, 'Employee not found.', 'error');
    return res.redirect(`/attendance?date=${encodeURIComponent(formatDate(safeDate))}`);
  }

  upsertAttendance({
    employeeId,
    date: safeDate,
    status,
    markSource: 'manual',
    notes,
    recordedByUserId: actorUserId(req),
  });

  setFlash(req, 'Attendance updated.', 'success');
  return res.redirect(`/attendance?date=${encodeURIComponent(formatDate(safeDate))}`);
});

app.get('/leaves', requireRoles('admin'), (req, res) => {
  const leaves = listLeaveRecords();
  const employees = listEmployees().filter((item) => item.status === 'active');

  return res.render('leaves', {
    pageTitle: 'Leave Management',
    leaves,
    employees,
    canReview: true,
  });
});

app.post('/leaves/request', requireRoles('admin'), (req, res) => {
  const schema = z.object({
    employeeId: z.string().uuid(),
    startDate: z.string().trim().min(1),
    endDate: z.string().trim().min(1),
    reason: z.string().trim().max(350).optional().or(z.literal('')),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    setFlash(req, 'Invalid leave request form.', 'error');
    return res.redirect('/leaves');
  }

  const { employeeId, startDate, endDate, reason } = parsed.data;
  const startDateIso = parseDateIn(startDate, null);
  const endDateIso = parseDateIn(endDate, null);

  if (!startDateIso || !endDateIso) {
    setFlash(req, 'Invalid date format. Use dd-mm-yyyy.', 'error');
    return res.redirect('/leaves');
  }

  const employee = getEmployeeById(employeeId);
  if (!employee) {
    setFlash(req, 'Employee not found.', 'error');
    return res.redirect('/leaves');
  }

  if (startDateIso > endDateIso) {
    setFlash(req, 'Leave start date must be before end date.', 'error');
    return res.redirect('/leaves');
  }

  createLeaveRequest({
    employeeId,
    requestedByUserId: actorUserId(req),
    startDate: startDateIso,
    endDate: endDateIso,
    reason,
  });

  setFlash(req, 'Leave request submitted.', 'success');
  return res.redirect('/leaves');
});

app.post('/leaves/:id/status', requireRoles('admin'), (req, res) => {
  const leaveId = req.params.id;
  const status = req.body.status;

  if (!['approved', 'rejected'].includes(status)) {
    setFlash(req, 'Invalid leave status.', 'error');
    return res.redirect('/leaves');
  }

  const updated = updateLeaveStatus({ leaveId, status, reviewedByUserId: actorUserId(req) });

  if (!updated) {
    setFlash(req, 'Leave record not found.', 'error');
    return res.redirect('/leaves');
  }

  if (status === 'approved') {
    const dates = dateRange(updated.start_date, updated.end_date);
    for (const date of dates) {
      upsertAttendance({
        employeeId: updated.employee_id,
        date,
        status: 'leave',
        markSource: 'manual',
        notes: 'Auto-marked from approved leave.',
        recordedByUserId: actorUserId(req),
      });
    }
  }

  setFlash(req, `Leave request ${status}.`, 'success');
  return res.redirect('/leaves');
});

app.get('/biometric', requireRoles('admin'), (_req, res) => {
  return res.redirect('/biometric-management');
});

app.get('/biometric-management', requireRoles('admin'), (req, res) => {
  const employees = listEmployees().filter((item) => item.status === 'active');
  const summaries = {};

  for (const employee of employees) {
    summaries[employee.id] = getEmployeeBiometricSummary(employee.id);
  }

  const biometricLogs = listBiometricLogs(120);
  const metrics = getBiometricMetrics();

  return res.render('biometric-management', {
    pageTitle: 'Biometric Management',
    employees,
    summaries,
    biometricLogs,
    metrics,
  });
});

app.get('/api/biometric/employee-summary/:employeeId', requireRoles('admin'), (req, res) => {
  const employee = getEmployeeById(req.params.employeeId);
  if (!employee) {
    return res.status(404).json({ ok: false, error: 'Employee not found.' });
  }

  const summary = getEmployeeBiometricSummary(req.params.employeeId);
  return res.json({ ok: true, summary });
});

app.post('/api/biometric/face/enroll', requireRoles('admin'), (req, res) => {
  try {
    const schema = z.object({
      employeeId: z.string().uuid(),
      descriptor: z.array(z.number()).min(64).max(512),
    });

    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ ok: false, error: 'Invalid face enrollment payload.' });
    }

    const employee = getEmployeeById(parsed.data.employeeId);
    if (!employee) {
      return res.status(404).json({ ok: false, error: 'Employee not found.' });
    }

    storeFaceProfile({
      employeeId: parsed.data.employeeId,
      descriptor: normalizeDescriptor(parsed.data.descriptor),
      createdByUserId: actorUserId(req),
    });

    addBiometricLog({
      employeeId: parsed.data.employeeId,
      userId: actorUserId(req),
      method: 'face',
      success: true,
      details: 'Face profile enrolled.',
    });

    return res.json({ ok: true, message: 'Face profile enrolled successfully.' });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.post('/api/biometric/face/delete', requireRoles('admin'), (req, res) => {
  try {
    const schema = z.object({ employeeId: z.string().uuid() });

    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ ok: false, error: 'Invalid request payload.' });
    }

    const employee = getEmployeeById(parsed.data.employeeId);
    if (!employee) {
      return res.status(404).json({ ok: false, error: 'Employee not found.' });
    }

    const removed = deleteFaceProfile(parsed.data.employeeId);

    addBiometricLog({
      employeeId: parsed.data.employeeId,
      userId: actorUserId(req),
      method: 'face',
      success: true,
      details: `Face profile deleted (rows=${removed}).`,
    });

    return res.json({ ok: true, message: removed ? 'Face profile removed.' : 'No face profile existed.' });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.post('/api/biometric/face/verify', requireRoles('admin'), (req, res) => {
  try {
    const schema = z.object({
      employeeId: z.string().uuid(),
      descriptor: z.array(z.number()).min(64).max(512),
      date: z.string().trim().min(1).optional(),
    });

    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ ok: false, error: 'Invalid face verification payload.' });
    }

    const employee = getEmployeeById(parsed.data.employeeId);
    if (!employee) {
      return res.status(404).json({ ok: false, error: 'Employee not found.' });
    }

    const stored = getFaceProfile(parsed.data.employeeId);
    if (!stored) {
      addBiometricLog({
        employeeId: parsed.data.employeeId,
        userId: actorUserId(req),
        method: 'face',
        success: false,
        details: 'No profile found.',
      });
      return res.status(404).json({ ok: false, error: 'No face profile found for this employee.' });
    }

    const result = isFaceMatch({
      storedDescriptor: stored,
      candidateDescriptor: normalizeDescriptor(parsed.data.descriptor),
      threshold: 0.5,
    });

    if (!result.matched) {
      addBiometricLog({
        employeeId: parsed.data.employeeId,
        userId: actorUserId(req),
        method: 'face',
        success: false,
        details: `Mismatch distance=${result.distance.toFixed(4)}`,
      });
      return res.status(401).json({
        ok: false,
        matched: false,
        distance: result.distance,
        error: 'Face mismatch. Re-enroll if this persists.',
      });
    }

    const date = parseDateIn(parsed.data.date, isoToday());
    upsertAttendance({
      employeeId: parsed.data.employeeId,
      date,
      status: 'present',
      markSource: 'face',
      notes: 'Marked by biometric management verification.',
      recordedByUserId: actorUserId(req),
    });

    addBiometricLog({
      employeeId: parsed.data.employeeId,
      userId: actorUserId(req),
      method: 'face',
      success: true,
      details: `Matched distance=${result.distance.toFixed(4)}`,
    });

    return res.json({
      ok: true,
      matched: true,
      distance: result.distance,
      message: 'Face verified and attendance marked present.',
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.post('/api/attendance/face/identify', requireKioskOrAdmin, (req, res) => {
  try {
    const schema = z.object({
      descriptor: z.array(z.number()).min(64).max(512),
      facesDetected: z.number().int().min(0).max(10),
      lightingOk: z.boolean(),
      livenessPassed: z.boolean(),
    });

    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ ok: false, error: 'Invalid face analysis payload.' });
    }

    if (parsed.data.facesDetected === 0) {
      return res.status(400).json({ ok: false, error: 'No face detected.' });
    }

    if (parsed.data.facesDetected > 1) {
      return res.status(400).json({ ok: false, error: 'Multiple faces detected. Keep only one face in frame.' });
    }

    if (!parsed.data.lightingOk) {
      return res.status(400).json({ ok: false, error: 'Low lighting detected. Improve lighting and retry.' });
    }

    if (!parsed.data.livenessPassed) {
      return res.status(400).json({ ok: false, error: 'Liveness check failed. Please blink or move slightly.' });
    }

    const candidateDescriptor = normalizeDescriptor(parsed.data.descriptor);
    const profiles = listFaceProfilesForMatching();

    if (!profiles.length) {
      return res.status(404).json({ ok: false, error: 'No enrolled face profiles available.' });
    }

    let best = null;
    for (const profile of profiles) {
      const result = isFaceMatch({
        storedDescriptor: profile.descriptor,
        candidateDescriptor,
        threshold: 0.5,
      });

      if (!best || result.distance < best.distance) {
        best = {
          profile,
          distance: result.distance,
          matched: result.matched,
        };
      }
    }

    const confidence = Math.max(0, Math.min(1, 1 - best.distance / 0.5));

    if (!best.matched) {
      addBiometricLog({
        employeeId: null,
        userId: actorUserId(req),
        method: 'face',
        success: false,
        details: `Attendance identify failed. Best distance=${best.distance.toFixed(4)}`,
      });

      return res.status(401).json({
        ok: false,
        error: 'Face not recognized. Retry or use biometric management to re-enroll.',
        confidence,
      });
    }

    addBiometricLog({
      employeeId: best.profile.employeeId,
      userId: actorUserId(req),
      method: 'face',
      success: true,
      details: `Attendance identify success. Distance=${best.distance.toFixed(4)}`,
    });

    return res.json({
      ok: true,
      confidence,
      distance: best.distance,
      employee: {
        id: best.profile.employeeId,
        employeeCode: best.profile.employeeCode,
        fullName: best.profile.fullName,
        position: best.profile.position,
      },
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.post('/api/attendance/confirm', requireKioskOrAdmin, (req, res) => {
  try {
    const schema = z.object({
      employeeId: z.string().uuid(),
      confidence: z.number().min(0).max(1).optional(),
    });

    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ ok: false, error: 'Invalid attendance confirmation payload.' });
    }

    const employee = getEmployeeById(parsed.data.employeeId);
    if (!employee || employee.status !== 'active') {
      return res.status(404).json({ ok: false, error: 'Employee not found or inactive.' });
    }

    const date = isoToday();
    const confidenceText =
      parsed.data.confidence == null ? '' : ` (confidence ${(parsed.data.confidence * 100).toFixed(1)}%)`;

    const record = upsertAttendance({
      employeeId: parsed.data.employeeId,
      date,
      status: 'present',
      markSource: 'face',
      notes: `Confirmed in attendance mode${confidenceText}.`,
      recordedByUserId: actorUserId(req),
    });

    return res.json({
      ok: true,
      message: `${employee.full_name} marked present.`,
      record,
    });
  } catch (error) {
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.get('/api/attendance/today-log', requireKioskOrAdmin, (req, res) => {
  const date = isoToday();
  const entries = listTodayAttendanceLog(date, 40);

  return res.json({
    ok: true,
    date,
    displayDate: formatDate(date),
    entries: entries.map((entry) => ({
      ...entry,
      updated_at_display: formatDateTime(entry.updated_at),
    })),
  });
});

app.use((_req, res) => {
  res.status(404).render('error', {
    pageTitle: 'Not Found',
    message: 'The page you requested does not exist.',
  });
});

app.use((error, _req, res, _next) => {
  res.status(500).render('error', {
    pageTitle: 'Server Error',
    message: error.message || 'Unexpected error occurred.',
  });
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Chicky Bites Attendance running at ${ORIGIN}`);
});
