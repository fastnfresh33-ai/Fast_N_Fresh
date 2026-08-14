const { Table, Order } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// GET /api/tables — list with a computed liveStatus + open order count so the
// UI never has to guess; `status` itself may lag (e.g. 'reserved') by design.
const listTables = asyncHandler(async (req, res) => {
  const tables = await Table.find({ active: true }).sort({ name: 1 });

  const openCounts = await Order.aggregate([
    { $match: { status: 'open', table: { $ne: null } } },
    { $group: { _id: '$table', count: { $sum: 1 } } },
  ]);
  const countMap = new Map(openCounts.map((c) => [c._id.toString(), c.count]));

  const data = tables.map((t) => {
    const openOrderCount = countMap.get(t._id.toString()) || 0;
    return {
      ...t.toObject(),
      openOrderCount,
      liveStatus: openOrderCount > 0 ? 'occupied' : t.status === 'reserved' ? 'reserved' : 'available',
    };
  });

  res.json({ success: true, data });
});

// GET /api/tables/:id — table + all its currently open (unpaid) orders.
const getTable = asyncHandler(async (req, res) => {
  const table = await Table.findOne({ _id: req.params.id, active: true });
  if (!table) throw new ApiError(404, 'Table not found.');

  const openOrders = await Order.find({ table: table._id, status: 'open' })
    .populate('staff', 'name')
    .populate('customer', 'name phone')
    .sort({ createdAt: 1 });

  res.json({ success: true, data: { table, openOrders } });
});

const createTable = asyncHandler(async (req, res) => {
  const { name, capacity } = req.body;
  if (!name || !name.trim()) throw new ApiError(400, 'Table name/number is required.');

  const table = await Table.create({ name: name.trim(), capacity: capacity || 4 });
  res.status(201).json({ success: true, data: table });
});

const updateTable = asyncHandler(async (req, res) => {
  const table = await Table.findOne({ _id: req.params.id, active: true });
  if (!table) throw new ApiError(404, 'Table not found.');

  const { name, capacity, status } = req.body;
  if (name !== undefined) table.name = name.trim();
  if (capacity !== undefined) table.capacity = capacity;
  if (status !== undefined) {
    if (!['available', 'occupied', 'reserved'].includes(status)) {
      throw new ApiError(400, 'Invalid status.');
    }
    // Manually marking "occupied" isn't meaningful — that's derived from open
    // orders — but 'reserved' and manually resetting to 'available' are.
    if (status === 'occupied') throw new ApiError(400, "Table status becomes 'occupied' automatically once an order is opened on it.");
    table.status = status;
  }

  await table.save();
  res.json({ success: true, data: table });
});

// Deactivate (never hard-delete — preserves historical order/report data).
const deleteTable = asyncHandler(async (req, res) => {
  const table = await Table.findById(req.params.id);
  if (!table) throw new ApiError(404, 'Table not found.');

  const hasOpenOrders = await Order.exists({ table: table._id, status: 'open' });
  if (hasOpenOrders) {
    throw new ApiError(409, 'Cannot deactivate a table with active (unpaid) orders on it.');
  }

  table.active = false;
  await table.save();
  res.json({ success: true, message: 'Table deactivated.' });
});

module.exports = { listTables, getTable, createTable, updateTable, deleteTable };
