// One-off migration: assigns a QR ordering `number` to every existing Table
// that doesn't have one yet, by extracting the digits from its name
// (e.g. "Table 5" -> 5). Safe to re-run — it only touches tables that are
// still missing a number, and skips (with a warning) any table whose name
// has no digits or whose derived number is already taken by another table.
//
// Run once after deploying this change:
//   node src/utils/migrateTableNumbers.js

require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const { Table } = require('../models');

async function migrate() {
  await connectDB();

  const tables = await Table.find({ number: { $exists: false } }).sort({ name: 1 });
  console.log(`Found ${tables.length} table(s) without a QR number.`);

  let assigned = 0;
  let skipped = 0;

  for (const table of tables) {
    const match = table.name.match(/(\d+)/);
    if (!match) {
      console.warn(`  SKIP: "${table.name}" has no digits to derive a number from. Set it manually in Admin.`);
      skipped += 1;
      continue;
    }

    const candidate = Number(match[1]);
    const clash = await Table.findOne({ number: candidate });
    if (clash) {
      console.warn(`  SKIP: "${table.name}" -> ${candidate} is already used by "${clash.name}". Set it manually in Admin.`);
      skipped += 1;
      continue;
    }

    table.number = candidate;
    await table.save();
    console.log(`  OK: "${table.name}" -> QR #${candidate}`);
    assigned += 1;
  }

  console.log(`\nDone. Assigned: ${assigned}, skipped: ${skipped}.`);
  if (skipped > 0) {
    console.log('Skipped tables can be fixed manually from Admin > Tables > Edit (or the QR Management screen).');
  }

  await mongoose.disconnect();
  process.exit(0);
}

migrate().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
