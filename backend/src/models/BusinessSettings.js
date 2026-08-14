const mongoose = require('mongoose');

// Singleton document holding cafe-wide configuration.
const businessSettingsSchema = new mongoose.Schema(
  {
    singletonKey: { type: String, default: 'MAIN', unique: true },

    cafeName: { type: String, default: 'FAST N FRESH CAFE' },
    tagline: { type: String, default: 'Fresh • Fast • Delicious' },
    phone: { type: String, default: '' },
    address: { type: String, default: '' },
    gstNumber: { type: String, default: '' },
    logoUrl: { type: String, default: '' },
    upiId: { type: String, default: '' },

    receiptFooter: { type: String, default: 'Thank you for visiting!\nVisit Again' },
    taxEnabled: { type: Boolean, default: false },
    taxPercent: { type: Number, default: 0 },
    defaultDiscount: { type: Number, default: 0 },
    currencySymbol: { type: String, default: '₹' },

    primaryColor: { type: String, default: '#0E7C5A' },
  },
  { timestamps: true }
);

businessSettingsSchema.statics.getSettings = async function getSettings() {
  let settings = await this.findOne({ singletonKey: 'MAIN' });
  if (!settings) {
    settings = await this.create({ singletonKey: 'MAIN' });
  }
  return settings;
};

module.exports = mongoose.model('BusinessSettings', businessSettingsSchema);
