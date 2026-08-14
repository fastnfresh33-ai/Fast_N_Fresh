const { User } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// GET /api/users — admin-only directory of all staff/manager (and admin)
// accounts, for the Admin "Staff/Users Management" screen.
const listUsers = asyncHandler(async (req, res) => {
  const { role } = req.query;
  const filter = {};
  if (role) filter.role = role;

  const users = await User.find(filter).sort({ role: 1, name: 1 });
  res.json({ success: true, data: users.map((u) => u.toSafeJSON()) });
});

// POST /api/users — create a Staff or Manager account. Creating another
// Admin account is intentionally not exposed here — preserves the existing
// admin seed/auth flow as the only way an admin account is created.
const createUser = asyncHandler(async (req, res) => {
  const { name, phone, username, password, role } = req.body;

  if (!name || !phone || !username || !password) {
    throw new ApiError(400, 'Name, phone, username and password are all required.');
  }
  if (!['staff', 'manager'].includes(role)) {
    throw new ApiError(400, "Role must be 'staff' or 'manager'.");
  }
  if (password.length < 6) {
    throw new ApiError(400, 'Password must be at least 6 characters.');
  }

  const existing = await User.findOne({ username: username.toLowerCase().trim() });
  if (existing) throw new ApiError(409, 'This username is already taken.');

  const user = new User({
    name: name.trim(),
    phone: phone.trim(),
    username: username.toLowerCase().trim(),
    role,
  });
  await user.setPassword(password);
  await user.save();

  res.status(201).json({ success: true, data: user.toSafeJSON() });
});

// PATCH /api/users/:id/role  { role: 'staff' | 'manager' }
// Admin-only. Never allows changing to/from 'admin' through this endpoint —
// that protects against accidentally creating or demoting admin accounts.
const changeRole = asyncHandler(async (req, res) => {
  const { role } = req.body;
  if (!['staff', 'manager'].includes(role)) {
    throw new ApiError(400, "Role must be 'staff' or 'manager'.");
  }

  const user = await User.findById(req.params.id);
  if (!user) throw new ApiError(404, 'User not found.');
  if (user.role === 'admin') {
    throw new ApiError(403, 'Admin accounts cannot have their role changed here.');
  }

  user.role = role;
  user.tokenVersion += 1; // force re-login so the new role takes effect immediately
  await user.save();

  res.json({ success: true, data: user.toSafeJSON() });
});

// PATCH /api/users/:id/status  { status: 'active' | 'inactive' }
// Admin-only. Refuses to deactivate the last remaining active admin account.
const changeStatus = asyncHandler(async (req, res) => {
  const { status } = req.body;
  if (!['active', 'inactive'].includes(status)) {
    throw new ApiError(400, "Status must be 'active' or 'inactive'.");
  }

  const user = await User.findById(req.params.id);
  if (!user) throw new ApiError(404, 'User not found.');

  if (user.role === 'admin' && status === 'inactive') {
    const activeAdminCount = await User.countDocuments({ role: 'admin', status: 'active' });
    if (activeAdminCount <= 1) {
      throw new ApiError(409, 'Cannot deactivate the only remaining active admin account.');
    }
  }

  user.status = status;
  if (status === 'inactive') user.tokenVersion += 1; // force logout
  await user.save();

  res.json({ success: true, data: user.toSafeJSON() });
});

module.exports = { listUsers, createUser, changeRole, changeStatus };
