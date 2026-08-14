const { Product, InventoryTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

// GET /api/inventory — current stock levels for all tracked products
const getInventory = asyncHandler(async (req, res) => {
  const products = await Product.find({ isDeleted: false, trackInventory: true })
    .populate('category', 'name')
    .sort({ name: 1 });

  const lowStock = products.filter((p) => p.stock <= p.lowStockThreshold);

  res.json({
    success: true,
    data: {
      products,
      lowStockCount: lowStock.length,
      lowStockProducts: lowStock,
    },
  });
});

// GET /api/inventory/:productId/history
const getProductHistory = asyncHandler(async (req, res) => {
  const history = await InventoryTransaction.find({ product: req.params.productId })
    .populate('recordedBy', 'name')
    .sort({ createdAt: -1 })
    .limit(200);
  res.json({ success: true, data: history });
});

// POST /api/inventory/adjust  { productId, type: 'STOCK_IN'|'STOCK_OUT'|'ADJUSTMENT', quantity, reason }
const adjustInventory = asyncHandler(async (req, res) => {
  const { productId, type, quantity, reason } = req.body;

  if (!['STOCK_IN', 'STOCK_OUT', 'ADJUSTMENT'].includes(type)) {
    throw new ApiError(400, 'type must be STOCK_IN, STOCK_OUT, or ADJUSTMENT.');
  }
  const qty = Number(quantity);
  if (!Number.isFinite(qty) || qty === 0) {
    throw new ApiError(400, 'A non-zero quantity is required.');
  }

  const product = await Product.findOne({ _id: productId, isDeleted: false });
  if (!product) throw new ApiError(404, 'Product not found.');

  let signedQty;
  if (type === 'STOCK_IN') signedQty = Math.abs(qty);
  else if (type === 'STOCK_OUT') signedQty = -Math.abs(qty);
  else signedQty = qty; // ADJUSTMENT can be positive or negative directly (set delta)

  const newStock = product.stock + signedQty;
  if (newStock < 0) throw new ApiError(400, `Adjustment would result in negative stock (${newStock}).`);

  product.stock = newStock;
  await product.save();

  const transaction = await InventoryTransaction.create({
    product: product._id,
    type,
    quantity: signedQty,
    stockAfter: product.stock,
    reason,
    recordedBy: req.user._id,
  });

  res.status(201).json({ success: true, data: { product, transaction } });
});

module.exports = { getInventory, getProductHistory, adjustInventory };
