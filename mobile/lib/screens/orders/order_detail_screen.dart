import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../models/misc_models.dart';
import '../../services/order_service.dart';
import '../../services/misc_services.dart';
import '../../services/receipt_service.dart';
import '../../providers/auth_provider.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _orderService = OrderService();
  final _receiptService = ReceiptService();
  Order? _order;
  BusinessSettings _settings = BusinessSettings();
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_orderService.getById(widget.orderId), SettingsService().get()]);
      setState(() {
        _order = results[0] as Order;
        _settings = results[1] as BusinessSettings;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load this order.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _voidOrder() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will restock inventory and reverse any UDHAR effect. This cannot be undone.'),
            const SizedBox(height: 12),
            TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void Order', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _orderService.voidOrder(widget.orderId, reason: reasonController.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(_order != null ? 'Bill #${_order!.orderNumber}' : 'Order'),
        actions: [
          if (_order != null && _order!.status == 'completed') ...[
            IconButton(icon: const Icon(Icons.print_outlined), onPressed: _busy ? null : () => _receiptService.printReceipt(_order!, _settings)),
            IconButton(icon: const Icon(Icons.share_outlined), onPressed: _busy ? null : () => _receiptService.shareReceipt(_order!, _settings)),
            if (isAdmin) IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: _busy ? null : _voidOrder),
          ],
        ],
      ),
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final order = _order!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (order.status == 'voided')
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.block, color: AppColors.danger, size: 18),
              SizedBox(width: 8),
              Text('This order has been voided', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ]),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Formatters.dateTime(order.createdAt), style: Theme.of(context).textTheme.bodyMedium),
              Text(
                order.orderType == 'dine_in'
                    ? 'Dine-In${order.tableName != null ? ' · ${order.tableName}' : ''}${order.tableCustomerLabel != null ? ' · ${order.tableCustomerLabel}' : ''}'
                    : (order.orderType == 'delivery' ? 'Delivery' : 'Takeaway'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (order.staffName != null) Text('Attended by: ${order.staffName}', style: Theme.of(context).textTheme.bodyMedium),
              if (order.customerName != null) Text('Customer: ${order.customerName}', style: Theme.of(context).textTheme.bodyMedium),
              const Divider(height: 24),
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${item.name}  x${item.quantity}')),
                      Text(Formatters.currency(item.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  )),
              const Divider(height: 24),
              _row('Subtotal', Formatters.currency(order.subtotal)),
              if (order.discount > 0) _row('Discount', '- ${Formatters.currency(order.discount)}'),
              if (order.tax > 0) _row('Tax', Formatters.currency(order.tax)),
              const Divider(height: 20),
              _row('Grand Total', Formatters.currency(order.grandTotal), bold: true),
              const SizedBox(height: 12),
              _row('Payment Method', order.paymentMethod),
              if (order.paymentMethod == 'CASH' && order.amountReceived != null) ...[
                _row('Amount Received', Formatters.currency(order.amountReceived!)),
                _row('Change Returned', Formatters.currency(order.changeReturned)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 16 : 14)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: bold ? 17 : 14, color: bold ? AppColors.primary : AppColors.textPrimary)),
        ],
      ),
    );
  }
}
