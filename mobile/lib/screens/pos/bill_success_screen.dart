import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order.dart';
import '../../models/misc_models.dart';
import '../../services/receipt_service.dart';
import '../../services/misc_services.dart';

class BillSuccessScreen extends StatefulWidget {
  final Order order;
  const BillSuccessScreen({super.key, required this.order});

  @override
  State<BillSuccessScreen> createState() => _BillSuccessScreenState();
}

class _BillSuccessScreenState extends State<BillSuccessScreen> {
  final _receiptService = ReceiptService();
  BusinessSettings _settings = BusinessSettings();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsService().get();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Falls back to default settings — non-critical for this screen.
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not complete this action. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: AppColors.primary, size: 52),
              ),
              const SizedBox(height: 24),
              Text('Bill Created!', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text('Bill #${order.orderNumber}', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text(Formatters.currency(order.grandTotal), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const Spacer(),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runAction(() => _receiptService.printReceipt(order, _settings)),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runAction(() => _receiptService.shareReceipt(order, _settings)),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _runAction(() => _receiptService.shareTextSummary(order, _settings)),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share (WhatsApp / Others)'),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('New Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
