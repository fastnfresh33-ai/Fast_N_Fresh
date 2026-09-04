import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/order.dart';
import '../models/misc_models.dart';
import '../core/utils/formatters.dart';

/// Builds and shares/prints cafe receipts as PDFs.
///
/// This is structured as a standalone service so a Bluetooth thermal-printer
/// backend (ESC/POS) can be plugged in later without touching call sites —
/// screens just call [ReceiptService.shareReceipt] / [printReceipt].
class ReceiptService {
  /// Receipt width presets matching common thermal printer roll sizes.
  static const double width58mm = 58 * PdfPageFormat.mm;
  static const double width80mm = 80 * PdfPageFormat.mm;

  Future<Uint8List> buildReceiptPdf(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final doc = pw.Document();
    final pageWidth = widthMm * PdfPageFormat.mm;
    // PDF page boxes cannot use an infinite height reliably across Android,
    // Windows and physical printers. A generous finite roll length keeps the
    // existing receipt layout while producing a valid printable PDF.
    final estimatedHeight = (150 + (order.items.length * 10)).clamp(180, 500).toDouble() * PdfPageFormat.mm;
    final format = PdfPageFormat(
      pageWidth,
      estimatedHeight,
      marginAll: 10 * PdfPageFormat.mm / 3,
    );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  settings.cafeName,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  settings.tagline,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              if (settings.address.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    settings.address,
                    style: const pw.TextStyle(fontSize: 7),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              if (settings.phone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Ph: ${settings.phone}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              pw.SizedBox(height: 6),
              _dashedDivider(),
              pw.SizedBox(height: 4),
              _row(
                'Bill No:',
                '#${order.orderNumber.toString().padLeft(4, '0')}',
              ),
              _row('Date:', Formatters.date(order.createdAt)),
              _row('Time:', Formatters.time(order.createdAt)),
              _row(
                'Order Type:',
                order.orderType == 'dine_in'
                    ? 'Dine-In'
                    : (order.orderType == 'delivery'
                        ? 'Delivery'
                        : 'Takeaway'),
              ),
              if (order.tableName != null)
                _row('Table:', order.tableName!),
              if (order.staffName != null)
                _row('Staff:', order.staffName!),
              if (order.customerName != null)
                _row('Customer:', order.customerName!),
              pw.SizedBox(height: 4),
              _dashedDivider(),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text(
                      'Item',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'Qty',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'Amt',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              ...order.items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(
                          item.name,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'x${item.quantity}',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          Formatters.currency(item.total),
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              _dashedDivider(),
              pw.SizedBox(height: 4),
              _row(
                'Subtotal',
                Formatters.currency(order.subtotal),
              ),
              if (order.discount > 0)
                _row(
                  'Discount',
                  '- ${Formatters.currency(order.discount)}',
                ),
              if (order.tax > 0)
                _row(
                  'Tax',
                  Formatters.currency(order.tax),
                ),
              pw.SizedBox(height: 2),
              _dashedDivider(),
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'TOTAL',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Text(
                    Formatters.currency(order.grandTotal),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              _row('Payment:', order.paymentMethod),
              _row('Payment Status:', order.paymentStatus.toUpperCase()),
              if (order.paymentMethod == 'CASH' &&
                  order.amountReceived != null) ...[
                _row(
                  'Received:',
                  Formatters.currency(order.amountReceived!),
                ),
                _row(
                  'Change:',
                  Formatters.currency(order.changeReturned),
                ),
              ],
              if (order.paymentMethod == 'MIXED') ...[
                if (order.paymentBreakdown.cash > 0)
                  _row(
                    '  Cash:',
                    Formatters.currency(order.paymentBreakdown.cash),
                  ),
                if (order.paymentBreakdown.upi > 0)
                  _row(
                    '  UPI:',
                    Formatters.currency(order.paymentBreakdown.upi),
                  ),
                if (order.paymentBreakdown.credit > 0)
                  _row(
                    '  Credit:',
                    Formatters.currency(order.paymentBreakdown.credit),
                  ),
              ],
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  settings.receiptFooter,
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'Powered by GoogliXLabs',
                  style: pw.TextStyle(fontSize: 6, color: PdfColors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _dashedDivider() {
    return pw.Container(
      height: 0.6,
      color: PdfColors.grey600,
    );
  }

  Future<void> printReceipt(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final bytes = await buildReceiptPdf(
      order,
      settings,
      widthMm: widthMm,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
    );
  }

  Future<void> shareReceipt(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final bytes = await buildReceiptPdf(
      order,
      settings,
      widthMm: widthMm,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'bill_${order.orderNumber}.pdf',
    );
  }

  /// Shares a plain-text summary via the Android share sheet (e.g. WhatsApp)
  /// as a lightweight alternative to sharing the full PDF.
  Future<void> shareTextSummary(
    Order order,
    BusinessSettings settings,
  ) async {
    final buffer = StringBuffer()
      ..writeln(settings.cafeName)
      ..writeln('Bill #${order.orderNumber}')
      ..writeln(Formatters.dateTime(order.createdAt))
      ..writeln('---');

    for (final item in order.items) {
      buffer.writeln(
        '${item.name} x${item.quantity}  ${Formatters.currency(item.total)}',
      );
    }

    buffer
      ..writeln('---')
      ..writeln(
        'Total: ${Formatters.currency(order.grandTotal)}',
      )
      ..writeln('Payment: ${order.paymentMethod}')
      ..writeln(settings.receiptFooter)
      ..writeln('Powered by GoogliXLabs');

    await Share.share(buffer.toString());
  }
}