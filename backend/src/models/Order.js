const mongoose = require('mongoose');

// OrderItem is embedded as a sub-document of Order. This keeps order creation
// atomic and avoids extra round trips, while still being a clearly defined,
// independently validated schema (satisfies the OrderItem model requirement).
const orderItemSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
    name: { type: String, required: true }, // snapshot at time of sale
    price: { type: Number, required: true, min: 0 }, // snapshot selling price at time of sale
    quantity: { type: Number, required: true, min: 1 },
    total: { type: Number, required: true, min: 0 },
  },
  { _id: false }
);

const orderSchema = new mongoose.Schema(
  {
    orderNumber: { type: Number, required: true, unique: true, index: true }, // sequential, human-readable
    items: { type: [orderItemSchema], required: true, default: [] },

    // Order type: which channel this order came through.
    orderType: { type: String, enum: ['dine_in', 'takeaway', 'delivery'], default: 'takeaway', index: true },
    // Only set for dine_in orders. References the physical Table.
    table: { type: mongoose.Schema.Types.ObjectId, ref: 'Table' },
    // Distinguishes multiple simultaneous customers/orders on the same table
    // (e.g. "Customer 1", "Customer 2"). Purely a display label.
    tableCustomerLabel: { type: String, trim: true },
    // Only used for orderType = 'delivery'. Reuses the existing Customer
    // system where possible (see `customer` field below) — these fields
    // exist for delivery-specific details or walk-in delivery without a
    // saved Customer record.
    deliveryInfo: {
      address: { type: String, trim: true },
      phone: { type: String, trim: true },
    },

    subtotal: { type: Number, required: true, min: 0, default: 0 },
    discount: { type: Number, default: 0, min: 0 },
    tax: { type: Number, default: 0, min: 0 },
    grandTotal: { type: Number, required: true, min: 0, default: 0 },

    paymentMethod: { type: String, enum: ['CASH', 'UPI', 'CREDIT', 'MIXED'] }, // absent while status = 'open'
    paymentBreakdown: {
      cash: { type: Number, default: 0 },
      upi: { type: Number, default: 0 },
      credit: { type: Number, default: 0 },
    },
    upiReference: { type: String, trim: true },
    amountReceived: { type: Number }, // for cash, amount tendered
    changeReturned: { type: Number, default: 0 },

    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'Customer' }, // required only for CREDIT/MIXED-with-credit, or delivery customer
    notes: { type: String, trim: true },

    // The staff/manager/admin who is handling this order ("attendedBy").
    // Automatically set to the authenticated user at order-start time —
    // never entered manually. Kept as `staff` for backward compatibility
    // with the existing schema/reports; new code should read this as
    // "attendedBy".
    staff: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    // Optional handover trail if a different employee takes over the same
    // customer/order before it's completed. Most orders will have none.
    attendedByHistory: [
      {
        user: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        from: { type: Date },
        to: { type: Date },
      },
    ],

    status: { type: String, enum: ['open', 'completed', 'voided'], default: 'completed' },
    voidedAt: { type: Date },
    voidedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    voidReason: { type: String, trim: true },
  },
  { timestamps: true }
);

orderSchema.index({ createdAt: -1 });
orderSchema.index({ staff: 1, createdAt: -1 });
orderSchema.index({ customer: 1, createdAt: -1 });
orderSchema.index({ paymentMethod: 1 });
orderSchema.index({ table: 1, status: 1 });
orderSchema.index({ orderType: 1, createdAt: -1 });

module.exports = mongoose.model('Order', orderSchema);
