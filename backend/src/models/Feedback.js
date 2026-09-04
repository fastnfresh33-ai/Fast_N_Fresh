const mongoose = require('mongoose');

const feedbackSchema = new mongoose.Schema({
  order: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', required: true, index: true },
  orderNumber: { type: Number, required: true },
  rating: { type: Number, required: true, min: 1, max: 5 },
  comment: { type: String, trim: true, maxlength: 500, default: '' },
  customerName: { type: String, trim: true, maxlength: 100, default: '' },
  token: { type: String, required: true, index: true },
}, { timestamps: true });

feedbackSchema.index({ order: 1 }, { unique: true });
module.exports = mongoose.model('Feedback', feedbackSchema);
