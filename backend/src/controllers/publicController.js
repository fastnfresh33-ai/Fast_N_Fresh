const mongoose = require('mongoose');
const { Product, Category, Table, Order, Counter } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

const MAX_QUANTITY_PER_ITEM = 50; // guards against absurd/abusive quantities from a public endpoint

// GET /api/public/menu — read-only, customer-safe view of the catalog.
// Only ever returns fields a customer is allowed to see; no cost price,
// stock counts, low-stock thresholds, or soft-deleted/unavailable-category
// data ever leaves this endpoint.
const getPublicMenu = asyncHandler(async (req, res) => {
  const categories = await Category.find({ status: 'active' }).sort({ sortOrder: 1, name: 1 }).select('_id name sortOrder');

  const products = await Product.find({ isDeleted: false })
    .populate('category', 'name status')
    .sort({ name: 1 })
    .select('_id name category sellingPrice imageUrl status');

  const items = products
    .filter((p) => p.category && p.category.status === 'active')
    .map((p) => ({
      _id: p._id,
      name: p.name,
      category: p.category._id,
      categoryName: p.category.name,
      price: p.sellingPrice,
      image: p.imageUrl || '',
      available: p.status === 'available',
    }));

  res.json({
    success: true,
    categories: categories.map((c) => ({ _id: c._id, name: c.name })),
    items,
  });
});

// GET /api/public/tables/:number — resolves a QR table number to a display
// name and confirms it's a real, active table before the customer even
// starts browsing. Never trusts the number blindly: it must match an
// active Table document.
const getPublicTable = asyncHandler(async (req, res) => {
  const number = Number(req.params.number);
  if (!Number.isInteger(number) || number < 1) {
    throw new ApiError(400, 'Invalid table.');
  }

  const table = await Table.findOne({ number, active: true }).select('_id name number');
  if (!table) {
    throw new ApiError(404, 'This table QR code is not recognized. Please ask staff for help.');
  }

  res.json({ success: true, data: { tableId: table._id, tableNumber: table.number, tableName: table.name } });
});

// POST /api/public/orders — places a customer order from the QR menu.
// Creates an OPEN dine-in order on the given table using the existing
// order/table workflow, so staff pick it up exactly like any other
// unpaid table tab (edit items, checkout to bill it). No payment is taken
// here — payment still happens at the till via the existing POS checkout.
const createPublicOrder = asyncHandler(async (req, res) => {
  const { tableNumber, customerName, customerPhone, items, note } = req.body;

  const tableNum = Number(tableNumber);
  if (!Number.isInteger(tableNum) || tableNum < 1) {
    throw new ApiError(400, 'Invalid table number.');
  }

  if (customerName !== undefined && typeof customerName !== 'string') {
    throw new ApiError(400, 'Invalid customer name.');
  }
  if (customerName && customerName.trim().length > 100) {
    throw new ApiError(400, 'Customer name is too long.');
  }
  if (customerPhone !== undefined && customerPhone !== null && customerPhone !== '') {
    if (typeof customerPhone !== 'string' || !/^[0-9+\-\s]{6,20}$/.test(customerPhone.trim())) {
      throw new ApiError(400, 'Invalid phone number.');
    }
  }
  if (note !== undefined && (typeof note !== 'string' || note.length > 300)) {
    throw new ApiError(400, 'Note is too long.');
  }

  if (!Array.isArray(items) || items.length === 0) {
    throw new ApiError(400, 'Your cart is empty. Add at least one item.');
  }
  if (items.length > 50) {
    throw new ApiError(400, 'Too many distinct items in one order.');
  }

  // Validate/normalize item shape before touching the DB. Client-supplied
  // price/total/name are read nowhere below — only productId and quantity
  // are trusted, and even those are re-validated against the DB.
  const requestedItems = [];
  const seenProductIds = new Set();
  for (const raw of items) {
    const productId = raw && (raw.productId || raw.product);
    const quantity = Number(raw && raw.quantity);

    if (!productId || !mongoose.Types.ObjectId.isValid(productId)) {
      throw new ApiError(400, 'One of the items in your cart is invalid.');
    }
    if (!Number.isInteger(quantity) || quantity < 1) {
      throw new ApiError(400, 'Item quantities must be whole numbers of at least 1.');
    }
    if (quantity > MAX_QUANTITY_PER_ITEM) {
      throw new ApiError(400, `Quantity too high for one item (max ${MAX_QUANTITY_PER_ITEM}).`);
    }
    if (seenProductIds.has(String(productId))) {
      throw new ApiError(400, 'Duplicate item in cart. Please refresh and try again.');
    }
    seenProductIds.add(String(productId));
    requestedItems.push({ productId, quantity });
  }

  const table = await Table.findOne({ number: tableNum, active: true });
  if (!table) {
    throw new ApiError(404, 'This table QR code is not recognized. Please ask staff for help.');
  }

  const productIds = requestedItems.map((i) => i.productId);
  const products = await Product.find({ _id: { $in: productIds }, isDeleted: false }).populate('category', 'status');
  const productMap = new Map(products.map((p) => [p._id.toString(), p]));

  const orderItems = [];
  let subtotal = 0;

  for (const { productId, quantity } of requestedItems) {
    const product = productMap.get(String(productId));
    if (!product) throw new ApiError(400, 'One of the items in your cart is no longer available.');
    if (product.status !== 'available' || !product.category || product.category.status !== 'active') {
      throw new ApiError(400, `${product.name} is currently unavailable.`);
    }

    // Server-calculated price and line total only — client values are
    // never read or trusted anywhere in this flow.
    const lineTotal = round2(product.sellingPrice * quantity);
    subtotal = round2(subtotal + lineTotal);
    orderItems.push({ product: product._id, name: product.name, price: product.sellingPrice, quantity, total: lineTotal });
  }

  const grandTotal = subtotal; // no discount/tax applied to QR orders; staff can adjust at checkout like any open order

  const orderNumber = await Counter.getNextSequence('orderNumber');

  const order = await Order.create({
    orderNumber,
    items: orderItems,
    orderType: 'dine_in',
    orderSource: 'qr',
    table: table._id,
    tableCustomerLabel: (customerName && customerName.trim()) || undefined,
    qrCustomerContact: {
      name: (customerName && customerName.trim()) || undefined,
      phone: (customerPhone && customerPhone.trim()) || undefined,
    },
    subtotal,
    grandTotal,
    notes: note ? note.trim() : undefined,
    status: 'open',
    // staff intentionally omitted — schema allows this for orderSource 'qr';
    // it gets set automatically when staff checks the order out.
  });

  res.status(201).json({
    success: true,
    message: 'Order placed successfully.',
    data: {
      orderId: order._id,
      orderNumber: order.orderNumber,
      tableNumber: table.number,
      tableName: table.name,
      items: order.items,
      total: order.grandTotal,
    },
  });
});

module.exports = { getPublicMenu, getPublicTable, createPublicOrder };
