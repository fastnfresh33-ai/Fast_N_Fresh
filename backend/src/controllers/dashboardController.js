const { Order, Product, Customer } = require('../models');
const { asyncHandler } = require('../utils/apiError');
const { startOfDay, endOfDay, daysAgo, startOfWeek, startOfMonth } = require('../utils/dateRanges');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function summarize(orders) {
  const sales = orders.reduce((sum, o) => sum + o.grandTotal, 0);
  const cash = orders.reduce((sum, o) => sum + (o.paymentBreakdown?.cash || 0), 0);
  const upi = orders.reduce((sum, o) => sum + (o.paymentBreakdown?.upi || 0), 0);
  const credit = orders.reduce((sum, o) => sum + (o.paymentBreakdown?.credit || 0), 0);
  return {
    sales: round2(sales),
    orders: orders.length,
    cash: round2(cash),
    upi: round2(upi),
    credit: round2(credit),
  };
}

// GET /api/dashboard
const getDashboard = asyncHandler(async (req, res) => {
  const now = new Date();
  const todayStart = startOfDay(now);
  const todayEnd = endOfDay(now);

  const baseFilter = { status: 'completed' };
  // Staff see only their own numbers on the dashboard summary cards.
  if (req.user.role === 'staff') baseFilter.staff = req.user._id;

  const [todaysOrders, lowStockCount, outstandingAgg, recentOrders, topProductsAgg] = await Promise.all([
    Order.find({ ...baseFilter, createdAt: { $gte: todayStart, $lte: todayEnd } }),
    Product.countDocuments({ isDeleted: false, trackInventory: true, $expr: { $lte: ['$stock', '$lowStockThreshold'] } }),
    Customer.aggregate([
      { $match: { outstandingBalance: { $gt: 0 } } },
      { $group: { _id: null, total: { $sum: '$outstandingBalance' }, count: { $sum: 1 } } },
    ]),
    Order.find(baseFilter).populate('customer', 'name').sort({ createdAt: -1 }).limit(10),
    Order.aggregate([
      { $match: { ...baseFilter, createdAt: { $gte: daysAgo(30) } } },
      { $unwind: '$items' },
      { $group: { _id: '$items.name', qty: { $sum: '$items.quantity' } } },
      { $sort: { qty: -1 } },
      { $limit: 5 },
    ]),
  ]);

  const today = summarize(todaysOrders);
  const outstanding = outstandingAgg[0] || { total: 0, count: 0 };

  res.json({
    success: true,
    data: {
      today,
      lowStockCount,
      outstandingCredit: { total: round2(outstanding.total), customerCount: outstanding.count },
      recentOrders: recentOrders.map((o) => ({
        orderNumber: o.orderNumber,
        itemsSummary: o.items.map((i) => `${i.quantity} ${i.name}`).join(', '),
        grandTotal: o.grandTotal,
        paymentMethod: o.paymentMethod,
        createdAt: o.createdAt,
      })),
      topSellingProducts: topProductsAgg.map((p) => ({ name: p._id, quantitySold: p.qty })),
    },
  });
});

// GET /api/dashboard/sales-overview — Today / Yesterday / Week / Month + daily graph data
const getSalesOverview = asyncHandler(async (req, res) => {
  const now = new Date();
  const baseFilter = { status: 'completed' };
  if (req.user.role === 'staff') baseFilter.staff = req.user._id;

  const yesterday = daysAgo(1);

  const [todayOrders, yesterdayOrders, weekOrders, monthOrders, graphData] = await Promise.all([
    Order.find({ ...baseFilter, createdAt: { $gte: startOfDay(now), $lte: endOfDay(now) } }),
    Order.find({ ...baseFilter, createdAt: { $gte: startOfDay(yesterday), $lte: endOfDay(yesterday) } }),
    Order.find({ ...baseFilter, createdAt: { $gte: startOfWeek(now) } }),
    Order.find({ ...baseFilter, createdAt: { $gte: startOfMonth(now) } }),
    Order.aggregate([
      { $match: { ...baseFilter, createdAt: { $gte: daysAgo(13) } } },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } },
          sales: { $sum: '$grandTotal' },
          orders: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
    ]),
  ]);

  res.json({
    success: true,
    data: {
      today: summarize(todayOrders),
      yesterday: summarize(yesterdayOrders),
      thisWeek: summarize(weekOrders),
      thisMonth: summarize(monthOrders),
      last14Days: graphData.map((d) => ({ date: d._id, sales: round2(d.sales), orders: d.orders })),
    },
  });
});

module.exports = { getDashboard, getSalesOverview };
