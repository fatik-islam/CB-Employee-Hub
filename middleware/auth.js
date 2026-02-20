import { findUserById } from '../db.js';

export const attachCurrentUser = (req, _res, next) => {
  const userId = req.session?.userId;

  if (!userId) {
    req.currentUser = null;
    return next();
  }

  const user = findUserById(userId);

  if (!user) {
    req.session.userId = null;
    req.currentUser = null;
    return next();
  }

  req.currentUser = user;
  return next();
};

export const requireAuth = (req, res, next) => {
  if (!req.currentUser) {
    req.session.flash = { type: 'error', message: 'Please sign in first.' };
    return res.redirect('/login');
  }

  return next();
};

export const requireRoles = (...roles) => (req, res, next) => {
  if (!req.currentUser) {
    req.session.flash = { type: 'error', message: 'Please sign in first.' };
    return res.redirect('/login');
  }

  if (!roles.includes(req.currentUser.role)) {
    req.session.flash = { type: 'error', message: 'You are not authorized for this action.' };
    return res.redirect('/dashboard');
  }

  return next();
};

export const requireKioskOrAdmin = (req, res, next) => {
  const isAdmin = req.currentUser?.role === 'admin';
  const isKiosk = Boolean(req.session?.isKiosk);

  if (isAdmin || isKiosk) {
    return next();
  }

  const wantsJson =
    req.path.startsWith('/api/') ||
    req.headers.accept?.includes('application/json') ||
    req.headers['content-type']?.includes('application/json');

  if (wantsJson) {
    return res.status(401).json({ ok: false, error: 'Unauthorized access.' });
  }

  req.session.flash = { type: 'error', message: 'Please sign in to attendance mode.' };
  return res.redirect('/kiosk-login');
};
