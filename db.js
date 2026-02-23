import bcrypt from 'bcryptjs';
import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const configuredDbPath = (process.env.DB_PATH || 'chickybites.db').trim();
const dbPath = configuredDbPath === ':memory:' ? ':memory:' : path.resolve(configuredDbPath);
const legacyDbPath = path.resolve('chickybites.db');

const databaseRuntimeInfo = {
  configuredDbPath,
  resolvedDbPath: dbPath,
  legacyDbPath,
  usingMemoryDb: dbPath === ':memory:',
  targetExistsBeforeOpen: false,
  targetExistsAfterOpen: false,
  targetFileSizeBytes: 0,
  migratedFrom: null,
  migrationReason: null,
  migrationError: null,
  migratedWalFile: false,
  migratedShmFile: false,
};

const exists = (filePath) => {
  try {
    fs.accessSync(filePath, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
};

const safeFileSize = (filePath) => {
  try {
    return fs.statSync(filePath).size || 0;
  } catch {
    return 0;
  }
};

if (dbPath !== ':memory:') {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  databaseRuntimeInfo.targetExistsBeforeOpen = exists(dbPath);

  const canMigrateFromLegacy =
    !databaseRuntimeInfo.targetExistsBeforeOpen && dbPath !== legacyDbPath && exists(legacyDbPath);

  if (canMigrateFromLegacy) {
    try {
      fs.copyFileSync(legacyDbPath, dbPath);
      databaseRuntimeInfo.migratedFrom = legacyDbPath;
      databaseRuntimeInfo.migrationReason = 'target_missing_legacy_found';

      const legacyWal = `${legacyDbPath}-wal`;
      const legacyShm = `${legacyDbPath}-shm`;
      const targetWal = `${dbPath}-wal`;
      const targetShm = `${dbPath}-shm`;

      if (exists(legacyWal)) {
        fs.copyFileSync(legacyWal, targetWal);
        databaseRuntimeInfo.migratedWalFile = true;
      }

      if (exists(legacyShm)) {
        fs.copyFileSync(legacyShm, targetShm);
        databaseRuntimeInfo.migratedShmFile = true;
      }
    } catch (error) {
      databaseRuntimeInfo.migrationError = error.message;
    }
  }
}

const db = new Database(dbPath);
db.pragma('foreign_keys = ON');
db.pragma('journal_mode = WAL');

if (dbPath !== ':memory:') {
  databaseRuntimeInfo.targetExistsAfterOpen = exists(dbPath);
  databaseRuntimeInfo.targetFileSizeBytes = safeFileSize(dbPath);
}

const ATTENDANCE_STATUSES = ['present', 'absent', 'leave'];
const LEAVE_STATUSES = ['pending', 'approved', 'rejected'];

// NOTE:
// We keep the existing tables for compatibility. The app now runs admin-only,
// and employee login accounts are disabled at startup.
db.exec(`
  CREATE TABLE IF NOT EXISTS employees (
    id TEXT PRIMARY KEY,
    employee_code TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    phone TEXT,
    position TEXT,
    role TEXT NOT NULL CHECK(role IN ('manager', 'staff')),
    status TEXT NOT NULL CHECK(status IN ('active', 'inactive')) DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    employee_id TEXT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('admin', 'manager', 'staff')),
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE SET NULL
  );

  CREATE TABLE IF NOT EXISTS attendance_records (
    id TEXT PRIMARY KEY,
    employee_id TEXT NOT NULL,
    date TEXT NOT NULL,
    check_in_at TEXT,
    check_out_at TEXT,
    status TEXT NOT NULL CHECK(status IN ('present', 'absent', 'leave')),
    mark_source TEXT NOT NULL CHECK(mark_source IN ('manual', 'face')),
    notes TEXT,
    recorded_by_user_id TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(employee_id, date),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
    FOREIGN KEY (recorded_by_user_id) REFERENCES users(id) ON DELETE SET NULL
  );

  CREATE TABLE IF NOT EXISTS leave_records (
    id TEXT PRIMARY KEY,
    employee_id TEXT NOT NULL,
    requested_by_user_id TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    reason TEXT,
    status TEXT NOT NULL CHECK(status IN ('pending', 'approved', 'rejected')) DEFAULT 'pending',
    reviewed_by_user_id TEXT,
    reviewed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
    FOREIGN KEY (requested_by_user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (reviewed_by_user_id) REFERENCES users(id) ON DELETE SET NULL
  );

  CREATE TABLE IF NOT EXISTS face_profiles (
    id TEXT PRIMARY KEY,
    employee_id TEXT NOT NULL UNIQUE,
    descriptor_json TEXT NOT NULL,
    created_by_user_id TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL
  );

  CREATE TABLE IF NOT EXISTS biometric_logs (
    id TEXT PRIMARY KEY,
    employee_id TEXT,
    user_id TEXT,
    method TEXT NOT NULL CHECK(method IN ('face')),
    success INTEGER NOT NULL,
    details TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE SET NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
  );
`);

const seedAdmin = () => {
  const email = (process.env.ADMIN_EMAIL || 'admin@chickybites.com').trim().toLowerCase();
  const configuredPassword = process.env.ADMIN_PASSWORD?.trim();
  const password = configuredPassword || 'ChangeMe@123';

  const existing = db
    .prepare('SELECT id, password_hash FROM users WHERE email = ? LIMIT 1')
    .get(email);

  if (!existing) {
    const id = randomUUID();
    const hash = bcrypt.hashSync(password, 12);
    db.prepare(
      `INSERT INTO users (id, full_name, email, password_hash, role, active)
       VALUES (?, ?, ?, ?, 'admin', 1)`
    ).run(id, 'System Admin', email, hash);
  } else {
    db.prepare("UPDATE users SET role = 'admin', active = 1 WHERE id = ?").run(existing.id);

    // If ADMIN_PASSWORD is explicitly configured, keep the stored admin hash in sync.
    if (configuredPassword && !bcrypt.compareSync(configuredPassword, existing.password_hash)) {
      const hash = bcrypt.hashSync(configuredPassword, 12);
      db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(hash, existing.id);
    }
  }

  // Enforce admin-only sign-in mode.
  db.prepare("UPDATE users SET active = 0 WHERE role <> 'admin'").run();
};

seedAdmin();

const cleanAttendanceStatus = (status) => {
  if (!ATTENDANCE_STATUSES.includes(status)) {
    throw new Error('Invalid attendance status');
  }

  return status;
};

const cleanLeaveStatus = (status) => {
  if (!LEAVE_STATUSES.includes(status)) {
    throw new Error('Invalid leave status');
  }

  return status;
};

const cleanEmployeeRole = (role) => {
  if (!['manager', 'staff'].includes(role)) {
    throw new Error('Invalid employee role');
  }

  return role;
};

const cleanEmployeeStatus = (status) => {
  if (!['active', 'inactive'].includes(status)) {
    throw new Error('Invalid employee status');
  }

  return status;
};

export const findUserByEmail = (email) =>
  db
    .prepare('SELECT * FROM users WHERE email = ? AND active = 1 LIMIT 1')
    .get(email.toLowerCase());

export const findUserById = (id) =>
  db.prepare('SELECT * FROM users WHERE id = ? AND active = 1 LIMIT 1').get(id);

export const createEmployee = ({ employeeCode, fullName, phone, position, role }) => {
  const employeeId = randomUUID();
  const safeRole = cleanEmployeeRole(role);

  db.prepare(
    `INSERT INTO employees (id, employee_code, full_name, phone, position, role, status)
     VALUES (?, ?, ?, ?, ?, ?, 'active')`
  ).run(
    employeeId,
    employeeCode,
    fullName,
    phone || null,
    position || null,
    safeRole
  );

  return getEmployeeById(employeeId);
};

export const updateEmployee = ({
  employeeId,
  employeeCode,
  fullName,
  phone,
  position,
  role,
  status,
}) => {
  const safeRole = cleanEmployeeRole(role);
  const safeStatus = cleanEmployeeStatus(status);

  db.prepare(
    `UPDATE employees
     SET employee_code = ?,
         full_name = ?,
         phone = ?,
         position = ?,
         role = ?,
         status = ?
     WHERE id = ?`
  ).run(
    employeeCode,
    fullName,
    phone || null,
    position || null,
    safeRole,
    safeStatus,
    employeeId
  );

  return getEmployeeById(employeeId);
};

export const deleteEmployee = (employeeId) => {
  db.prepare('DELETE FROM employees WHERE id = ?').run(employeeId);
};

export const getEmployeeById = (id) =>
  db
    .prepare(
      `SELECT e.*
       FROM employees e
       WHERE e.id = ?`
    )
    .get(id);

export const listEmployees = () =>
  db
    .prepare(
      `SELECT e.*
       FROM employees e
       ORDER BY e.created_at DESC`
    )
    .all();

export const upsertAttendance = ({
  employeeId,
  date,
  status,
  markSource,
  notes,
  recordedByUserId,
}) => {
  const safeStatus = cleanAttendanceStatus(status);

  const existing = db
    .prepare('SELECT * FROM attendance_records WHERE employee_id = ? AND date = ?')
    .get(employeeId, date);

  if (existing) {
    db.prepare(
      `UPDATE attendance_records
       SET status = ?, mark_source = ?, notes = ?,
           check_in_at = CASE
             WHEN ? = 'present' AND check_in_at IS NULL THEN datetime('now')
             ELSE check_in_at
           END,
           updated_at = datetime('now'),
           recorded_by_user_id = ?
       WHERE id = ?`
    ).run(safeStatus, markSource, notes || null, safeStatus, recordedByUserId || null, existing.id);

    return db.prepare('SELECT * FROM attendance_records WHERE id = ?').get(existing.id);
  }

  const id = randomUUID();
  db.prepare(
    `INSERT INTO attendance_records (
      id, employee_id, date, check_in_at, status, mark_source, notes, recorded_by_user_id
    ) VALUES (?, ?, ?, CASE WHEN ? = 'present' THEN datetime('now') ELSE NULL END, ?, ?, ?, ?)`
  ).run(
    id,
    employeeId,
    date,
    safeStatus,
    safeStatus,
    markSource,
    notes || null,
    recordedByUserId || null
  );

  return db.prepare('SELECT * FROM attendance_records WHERE id = ?').get(id);
};

export const listAttendanceForDate = (date) =>
  db
    .prepare(
      `SELECT e.id AS employee_id, e.employee_code, e.full_name, e.position, e.status AS employee_status,
              a.id AS attendance_id, a.status AS attendance_status, a.mark_source, a.notes,
              a.check_in_at, a.check_out_at, a.updated_at
       FROM employees e
       LEFT JOIN attendance_records a
         ON a.employee_id = e.id AND a.date = ?
       WHERE e.status = 'active'
       ORDER BY e.full_name ASC`
    )
    .all(date);

export const getDashboardStats = () => {
  const today = new Date().toISOString().slice(0, 10);

  const totals = db
    .prepare(
      `SELECT
         SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS activeEmployees,
         SUM(CASE WHEN status = 'inactive' THEN 1 ELSE 0 END) AS inactiveEmployees
       FROM employees`
    )
    .get();

  const attendance = db
    .prepare(
      `SELECT
         SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS present,
         SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) AS absent,
         SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END) AS leaveCount
       FROM attendance_records
       WHERE date = ?`
    )
    .get(today);

  const pendingLeaves = db
    .prepare("SELECT COUNT(*) AS count FROM leave_records WHERE status = 'pending'")
    .get();

  return {
    today,
    activeEmployees: totals.activeEmployees || 0,
    inactiveEmployees: totals.inactiveEmployees || 0,
    present: attendance.present || 0,
    absent: attendance.absent || 0,
    leaveCount: attendance.leaveCount || 0,
    pendingLeaves: pendingLeaves.count || 0,
  };
};

export const createLeaveRequest = ({
  employeeId,
  requestedByUserId,
  startDate,
  endDate,
  reason,
}) => {
  const id = randomUUID();
  db.prepare(
    `INSERT INTO leave_records (id, employee_id, requested_by_user_id, start_date, end_date, reason, status)
     VALUES (?, ?, ?, ?, ?, ?, 'pending')`
  ).run(id, employeeId, requestedByUserId, startDate, endDate, reason || null);

  return db.prepare('SELECT * FROM leave_records WHERE id = ?').get(id);
};

export const listLeaveRecords = () =>
  db
    .prepare(
      `SELECT l.*, e.full_name, e.employee_code,
              req.full_name AS requested_by_name,
              rev.full_name AS reviewed_by_name
       FROM leave_records l
       JOIN employees e ON e.id = l.employee_id
       LEFT JOIN users req ON req.id = l.requested_by_user_id
       LEFT JOIN users rev ON rev.id = l.reviewed_by_user_id
       ORDER BY l.created_at DESC`
    )
    .all();

export const updateLeaveStatus = ({ leaveId, status, reviewedByUserId }) => {
  const safeStatus = cleanLeaveStatus(status);

  db.prepare(
    `UPDATE leave_records
     SET status = ?, reviewed_by_user_id = ?, reviewed_at = datetime('now')
     WHERE id = ?`
  ).run(safeStatus, reviewedByUserId || null, leaveId);

  return db.prepare('SELECT * FROM leave_records WHERE id = ?').get(leaveId);
};

export const storeFaceProfile = ({ employeeId, descriptor, createdByUserId }) => {
  const descriptorJson = JSON.stringify(descriptor);

  const existing = db
    .prepare('SELECT id FROM face_profiles WHERE employee_id = ? LIMIT 1')
    .get(employeeId);

  if (existing) {
    db.prepare(
      `UPDATE face_profiles
       SET descriptor_json = ?, created_by_user_id = ?, updated_at = datetime('now')
       WHERE employee_id = ?`
    ).run(descriptorJson, createdByUserId || null, employeeId);

    return;
  }

  db.prepare(
    `INSERT INTO face_profiles (id, employee_id, descriptor_json, created_by_user_id)
     VALUES (?, ?, ?, ?)`
  ).run(randomUUID(), employeeId, descriptorJson, createdByUserId || null);
};

export const deleteFaceProfile = (employeeId) => {
  const result = db.prepare('DELETE FROM face_profiles WHERE employee_id = ?').run(employeeId);
  return result.changes || 0;
};

export const getFaceProfile = (employeeId) => {
  const row = db
    .prepare('SELECT descriptor_json FROM face_profiles WHERE employee_id = ? LIMIT 1')
    .get(employeeId);

  if (!row) {
    return null;
  }

  try {
    return JSON.parse(row.descriptor_json);
  } catch {
    return null;
  }
};

export const addBiometricLog = ({ employeeId, userId, method, success, details }) => {
  db.prepare(
    `INSERT INTO biometric_logs (id, employee_id, user_id, method, success, details)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(
    randomUUID(),
    employeeId || null,
    userId || null,
    method,
    success ? 1 : 0,
    details || null
  );
};

export const listFaceProfilesForMatching = () => {
  const rows = db
    .prepare(
      `SELECT f.employee_id, f.descriptor_json, f.updated_at, e.employee_code, e.full_name, e.position
       FROM face_profiles f
       JOIN employees e ON e.id = f.employee_id
       WHERE e.status = 'active'`
    )
    .all();

  return rows
    .map((row) => {
      try {
        return {
          employeeId: row.employee_id,
          descriptor: JSON.parse(row.descriptor_json),
          updatedAt: row.updated_at,
          employeeCode: row.employee_code,
          fullName: row.full_name,
          position: row.position,
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean);
};

export const listTodayAttendanceLog = (date, limit = 30) =>
  db
    .prepare(
      `SELECT a.id, a.employee_id, a.status, a.mark_source, a.notes, a.updated_at,
              e.employee_code, e.full_name, e.position
       FROM attendance_records a
       JOIN employees e ON e.id = a.employee_id
       WHERE a.date = ?
       ORDER BY a.updated_at DESC
       LIMIT ?`
    )
    .all(date, limit);

export const listBiometricLogs = (limit = 80) =>
  db
    .prepare(
      `SELECT b.id, b.method, b.success, b.details, b.created_at,
              e.employee_code, e.full_name
       FROM biometric_logs b
       LEFT JOIN employees e ON e.id = b.employee_id
       WHERE b.method = 'face'
       ORDER BY b.created_at DESC
       LIMIT ?`
    )
    .all(limit);

export const getEmployeeBiometricSummary = (employeeId) =>
  db
    .prepare(
      `SELECT
          e.id AS employee_id,
          e.employee_code,
          e.full_name,
          e.position,
          CASE WHEN fp.employee_id IS NULL THEN 0 ELSE 1 END AS has_face_profile,
          fp.updated_at AS face_updated_at
       FROM employees e
       LEFT JOIN face_profiles fp ON fp.employee_id = e.id
       WHERE e.id = ?
       LIMIT 1`
    )
    .get(employeeId);

export const getBiometricMetrics = () => {
  const activeEmployees =
    db
      .prepare(
        `SELECT COUNT(*) AS count
         FROM employees
         WHERE status = 'active'`
      )
      .get().count || 0;

  const faceCount =
    db
      .prepare(
        `SELECT COUNT(*) AS count
         FROM face_profiles fp
         JOIN employees e ON e.id = fp.employee_id
         WHERE e.status = 'active'`
      )
      .get().count || 0;

  const attendanceStats = db
    .prepare(
      `SELECT
         SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS success_count,
         COUNT(*) AS total_count
       FROM attendance_records`
    )
    .get();

  const biometricStats = db
    .prepare(
      `SELECT
         SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) AS failed_count,
         COUNT(*) AS total_count
       FROM biometric_logs
       WHERE method = 'face'`
    )
    .get();

  const attendanceSuccessRate =
    attendanceStats.total_count > 0 ? attendanceStats.success_count / attendanceStats.total_count : 0;
  const failedVerificationRate =
    biometricStats.total_count > 0 ? biometricStats.failed_count / biometricStats.total_count : 0;

  let health = 'Healthy';
  if (failedVerificationRate > 0.2 || attendanceSuccessRate < 0.7) {
    health = 'Attention';
  }
  if (failedVerificationRate > 0.4 || attendanceSuccessRate < 0.5) {
    health = 'Critical';
  }

  return {
    totalFaceEnrolledEmployees: faceCount,
    pendingFaceEnrollment: Math.max(activeEmployees - faceCount, 0),
    attendanceSuccessRate,
    failedVerificationRate,
    systemHealth: health,
  };
};

export const isValidAttendanceStatus = (status) => ATTENDANCE_STATUSES.includes(status);
export const getDatabaseRuntimeInfo = () => ({ ...databaseRuntimeInfo });

export default db;
