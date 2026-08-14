const express = require('express');
const { listUsers, createUser, changeRole, changeStatus } = require('../controllers/userController');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

// Entire user/role-management section is admin-only.
router.use(protect, authorize('admin'));

router.get('/', listUsers);
router.post('/', createUser);
router.patch('/:id/role', changeRole);
router.patch('/:id/status', changeStatus);

module.exports = router;
