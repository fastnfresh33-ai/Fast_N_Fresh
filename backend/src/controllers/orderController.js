// GET /api/orders
// Staff can see:
// 1. Their own orders.
// 2. NEW/unattended QR orders created today.
// Admin/manager can see all orders.
const listOrders = asyncHandler(async (req, res) => {
  const {
    from,
    to,
    paymentMethod,
    staff,
    customer,
    search,
    status,
    orderType,
    table,
  } = req.query;

  const page = Math.max(
    parseInt(req.query.page, 10) || 1,
    1
  );

  const limit = Math.min(
    parseInt(req.query.limit, 10) || 30,
    200
  );

  const filter = {};

  // Payment filter
  if (paymentMethod) {
    filter.paymentMethod = paymentMethod;
  }

  // Order type filter
  if (orderType) {
    filter.orderType = orderType;
  }

  // Table filter
  if (table) {
    filter.table = table;
  }

  // Customer filter
  if (customer) {
    filter.customer = customer;
  }

  // Status filter
  if (status) {
    filter.status = status;
  }

  /*
   * STAFF VISIBILITY
   *
   * Staff can see:
   *
   * 1. Orders assigned to themselves.
   *
   * 2. Unattended QR orders that are NEW/open
   *    and were created TODAY.
   *
   * This is important because an old unattended QR order
   * must NOT continue appearing as a fresh NEW order every day.
   */
  if (req.user.role === 'staff') {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    if (!status) {
      /*
       * Default Orders screen:
       *
       * - Own orders
       * - Today's unattended QR NEW orders
       */
      filter.$or = [
        {
          staff: req.user._id,
        },
        {
          orderSource: 'qr',
          status: 'open',
          staff: {
            $exists: false,
          },
          createdAt: {
            $gte: startOfToday,
          },
        },
      ];
    } else {
      /*
       * When a specific status is requested,
       * respect that status for both branches.
       *
       * Example:
       * status=preparing
       * -> staff's preparing orders
       * -> today's unattended QR preparing orders
       */
      filter.$or = [
        {
          staff: req.user._id,
        },
        {
          orderSource: 'qr',
          status,
          staff: {
            $exists: false,
          },
          createdAt: {
            $gte: startOfToday,
          },
        },
      ];
    }
  } else if (staff) {
    /*
     * ADMIN / MANAGER
     *
     * They can filter by any staff member.
     */
    filter.staff = staff;
  }

  /*
   * DATE FILTER
   *
   * Used by Orders/History reporting.
   *
   * IMPORTANT:
   * We do NOT globally restrict history to today.
   * Old orders must remain available in history.
   */
  if (from || to) {
    filter.createdAt = {};

    if (from) {
      filter.createdAt.$gte = new Date(from);
    }

    if (to) {
      filter.createdAt.$lte = new Date(to);
    }
  }

  /*
   * ORDER NUMBER SEARCH
   */
  if (search) {
    const asNumber = Number(search);

    if (!Number.isNaN(asNumber)) {
      filter.orderNumber = asNumber;
    }
  }

  /*
   * FETCH ORDERS
   */
  const orders = await Order.find(filter)
    .populate(
      'customer',
      'name phone'
    )
    .populate(
      'staff',
      'name role'
    )
    .populate(
      'table',
      'name'
    )
    .sort({
      createdAt: -1,
    })
    .skip(
      (page - 1) * limit
    )
    .limit(limit);

  /*
   * TOTAL COUNT
   */
  const total = await Order.countDocuments(
    filter
  );

  /*
   * RESPONSE
   */
  res.json({
    success: true,
    data: orders,
    pagination: {
      page,
      limit,
      total,
      pages: Math.ceil(
        total / limit
      ),
    },
  });
});