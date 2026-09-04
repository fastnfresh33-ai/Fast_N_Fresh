import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/formatters.dart';
import '../models/misc_models.dart';
import '../models/order.dart';

/// Creates formal, thermal-printer-friendly cafe bills.
///
/// The layout intentionally follows a classic printed POS receipt:
/// centered cafe header, TAX INVOICE, compact bill metadata, fixed columns
/// for Item / Qty / Rate / Amount, discount, CGST/SGST, grand total, GST and
/// a simple closing footer. It works with both 58 mm and 80 mm rolls.
class ReceiptService {
  static const double width58mm = 58 * PdfPageFormat.mm;
  static const double width80mm = 80 * PdfPageFormat.mm;

  pw.Font get _mono => pw.Font.courier();
  pw.Font get _monoBold => pw.Font.courierBold();

  Future<Uint8List> buildReceiptPdf(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final doc = pw.Document();
    final pageWidth = widthMm * PdfPageFormat.mm;
    final is58 = widthMm <= 60;
    final chars = is58 ? 30 : 42;
    final fontSize = is58 ? 7.2 : 8.2;
    final smallSize = is58 ? 6.4 : 7.2;

    // Enough room for the receipt while remaining a finite, valid PDF page.
    final lineCount = 24 + order.items.length * 2;
    final estimatedHeight = (lineCount * (fontSize + 2.5) + 70).clamp(180, 500).toDouble() * PdfPageFormat.mm;
    final format = PdfPageFormat(
      pageWidth,
      estimatedHeight,
      marginLeft: 3.5 * PdfPageFormat.mm,
      marginRight: 3.5 * PdfPageFormat.mm,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
    );

    final totalTax = order.tax;
    final halfTax = totalTax / 2;
    final taxRate = settings.taxEnabled ? settings.taxPercent : 0;
    final halfRate = taxRate / 2;
    final discountPercent = order.subtotal > 0
        ? (order.discount / order.subtotal) * 100
        : 0;

    final cafeName = _fit(settings.cafeName, chars);
    final tagline = _fit(settings.tagline, chars);
    final address = _wrap(settings.address, chars);
    final phone = settings.phone.trim();
    final billNo = order.orderNumber.toString();
    final staff = (order.staffName?.trim().isNotEmpty ?? false)
        ? order.staffName!.trim()
        : 'COUNTER';

    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(
          base: _mono,
          bold: _monoBold,
        ),
        build: (_) {
          final widgets = <pw.Widget>[];

          widgets.add(_center(cafeName, fontSize + 2, bold: true));
          if (tagline.isNotEmpty) widgets.add(_center(tagline, fontSize));
          for (final line in address) {
            widgets.add(_center(line, smallSize));
          }
          if (phone.isNotEmpty) {
            widgets.add(_center('Ph: $phone', smallSize));
          }

          widgets.add(_gap(3));
          widgets.add(_center(_dash(chars), fontSize));
          widgets.add(_center('TAX INVOICE', fontSize + 1, bold: true));
          widgets.add(_center(_dash(chars), fontSize));
          widgets.add(_gap(3));

          widgets.add(
            _twoColumn(
              'Date: ${Formatters.date(order.createdAt)}',
              'Bill No. : $billNo',
              chars,
              fontSize,
            ),
          );
          widgets.add(_line('PBoy: $staff', fontSize));

          if (order.tableName?.trim().isNotEmpty ?? false) {
            widgets.add(_line('Table: ${order.tableName!.trim()}', fontSize));
          }

          widgets.add(_gap(3));
          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_threeColumnHeader(chars, fontSize));
          widgets.add(_line(_dash(chars), fontSize));

          for (final item in order.items) {
            final name = _fit(item.name, is58 ? 12 : 20);
            widgets.add(
              _fourColumn(
                name,
                item.quantity.toString(),
                _money(item.price),
                _money(item.total),
                chars,
                fontSize,
              ),
            );
          }

          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_gap(2));
          widgets.add(_summaryLine('Sub Total', _money(order.subtotal), chars, fontSize));

          if (order.discount > 0) {
            final pct = discountPercent.round();
            final label = pct > 0 ? 'Dis: @$pct%' : 'Discount';
            widgets.add(_summaryLine(label, _money(order.discount), chars, fontSize));
          }

          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_summaryLine('Net Total', _money(order.subtotal - order.discount), chars, fontSize));

          if (totalTax > 0) {
            widgets.add(_summaryLine(
              'CGST @${_rate(halfRate)}%',
              _money(halfTax),
              chars,
              fontSize,
            ));
            widgets.add(_summaryLine(
              'SGST @${_rate(halfRate)}%',
              _money(halfTax),
              chars,
              fontSize,
            ));
          }

          widgets.add(_line(_dash(chars), fontSize));
          widgets.add(_gap(1));
          widgets.add(_summaryLine('Grand Total', _money(order.grandTotal), chars, fontSize, bold: true, large: true));
          widgets.add(_line(_dash(chars), fontSize));

          if (settings.gstNumber.trim().isNotEmpty) {
            widgets.add(
              _twoColumn(
                'GST NO ${settings.gstNumber.trim()}',
                Formatters.time(order.createdAt),
                chars,
                smallSize,
              ),
            );
          } else {
            widgets.add(_line('GST NO: —', smallSize));
          }

          widgets.add(_gap(3));
          widgets.add(_center('E.&O.E.       Thank You       Visit Again', smallSize));
          widgets.add(_gap(2));

          final type = order.orderType == 'dine_in'
              ? 'Dine In'
              : order.orderType == 'delivery'
                  ? 'Delivery'
                  : 'Take Away';
          widgets.add(_center(type, fontSize + .5, bold: true));

          widgets.add(_gap(4));
          widgets.add(_center(settings.receiptFooter.replaceAll('\n', '  '), smallSize));
          widgets.add(_center('Powered by GoogliXLabs', 5.5));

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: widgets,
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _center(String text, double size, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: bold ? _monoBold : _mono,
          fontSize: size,
        ),
      ),
    );
  }

  pw.Widget _line(String text, double size) {
    return pw.Text(
      text,
      maxLines: 1,
      style: pw.TextStyle(font: _mono, fontSize: size),
    );
  }

  pw.Widget _twoColumn(String left, String right, int chars, double size) {
    final leftWidth = ((chars * .62).floor()).clamp(1, chars - 1);
    final rightWidth = chars - leftWidth;
    return pw.Text(
      _fit(left, leftWidth).padRight(leftWidth) + _fit(right, rightWidth).padLeft(rightWidth),
      maxLines: 1,
      style: pw.TextStyle(font: _mono, fontSize: size),
    );
  }

  pw.Widget _threeColumnHeader(int chars, double size) {
    final itemWidth = ((chars - 10) * .55).floor().clamp(8, chars);
    final remaining = chars - itemWidth;
    final qtyWidth = 4;
    final rateWidth = (remaining - qtyWidth) ~/ 2;
    final amountWidth = remaining - qtyWidth - rateWidth;
    return _line(
      _fit('Particulars', itemWidth).padRight(itemWidth) +
          _fit('Qty', qtyWidth).padLeft(qtyWidth) +
          _fit('Rate', rateWidth).padLeft(rateWidth) +
          _fit('Amount', amountWidth).padLeft(amountWidth),
      size,
    );
  }

  pw.Widget _fourColumn(
    String item,
    String qty,
    String rate,
    String amount,
    int chars,
    double size,
  ) {
    final itemWidth = ((chars - 12) * .52).floor().clamp(8, chars - 12);
    final qtyWidth = 4;
    final rateWidth = 7;
    final amountWidth = chars - itemWidth - qtyWidth - rateWidth;
    return _line(
      _fit(item, itemWidth).padRight(itemWidth) +
          _fit(qty, qtyWidth).padLeft(qtyWidth) +
          _fit(rate, rateWidth).padLeft(rateWidth) +
          _fit(amount, amountWidth).padLeft(amountWidth),
      size,
    );
  }

  pw.Widget _summaryLine(
    String label,
    String value,
    int chars,
    double size, {
    bool bold = false,
    bool large = false,
  }) {
    final valueWidth = large ? 10 : 10;
    final labelWidth = chars - valueWidth;
    return pw.Text(
      _fit(label, labelWidth).padRight(labelWidth) + _fit(value, valueWidth).padLeft(valueWidth),
      maxLines: 1,
      style: pw.TextStyle(
        font: bold ? _monoBold : _mono,
        fontSize: large ? size + 1.2 : size,
      ),
    );
  }

  pw.Widget _gap(double height) => pw.SizedBox(height: height);

  String _dash(int chars) => List.filled(chars, '-').join();

  String _fit(String value, int width) {
    final cleaned = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (cleaned.length <= width) return cleaned;
    if (width <= 1) return cleaned.substring(0, width);
    return cleaned.substring(0, width - 3) + '...';
  }

  List<String> _wrap(String value, int width) {
    final cleaned = value.replaceAll('\r', '').trim();
    if (cleaned.isEmpty) return const [];
    final result = <String>[];
    for (final sourceLine in cleaned.split('\n')) {
      var line = sourceLine.trim();
      while (line.length > width) {
        var cut = line.lastIndexOf(' ', width);
        if (cut <= 0) cut = width;
        result.add(line.substring(0, cut).trim());
        line = line.substring(cut).trim();
      }
      if (line.isNotEmpty) result.add(line);
    }
    return result;
  }

  String _money(num value) {
    return value.toStringAsFixed(2);
  }

  String _rate(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> printReceipt(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final bytes = await buildReceiptPdf(order, settings, widthMm: widthMm);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> shareReceipt(
    Order order,
    BusinessSettings settings, {
    double widthMm = 80,
  }) async {
    final bytes = await buildReceiptPdf(order, settings, widthMm: widthMm);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'bill_${order.orderNumber}.pdf',
    );
  }

  Future<void> shareTextSummary(
    Order order,
    BusinessSettings settings,
  ) async {
    final buffer = StringBuffer()
      ..writeln(settings.cafeName)
      ..writeln('TAX INVOICE')
      ..writeln('Bill No. : ${order.orderNumber}')
      ..writeln('Date     : ${Formatters.date(order.createdAt)}')
      ..writeln('Time     : ${Formatters.time(order.createdAt)}')
      ..writeln('---');

    for (final item in order.items) {
      buffer.writeln(
        '${item.name}  ${item.quantity}  ${_money(item.price)}  ${_money(item.total)}',
      );
    }

    buffer
      ..writeln('---')
      ..writeln('Sub Total : ${_money(order.subtotal)}')
      ..writeln('Discount  : ${_money(order.discount)}')
      ..writeln('Tax       : ${_money(order.tax)}')
      ..writeln('Grand Total: ${_money(order.grandTotal)}')
      ..writeln('Payment   : ${order.paymentMethod}')
      ..writeln(settings.receiptFooter)
      ..writeln('Powered by GoogliXLabs');

    await Share.share(buffer.toString());
  }
}
