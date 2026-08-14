import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _service = OrderService();
  List<Order> _orders = [];
  bool _loading = true;
  String? _error;
  String _filterRange = 'Today';
  String? _filterPayment;
  String? _filterOrderType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? get _fromDate {
    final now = DateTime.now();
    switch (_filterRange) {
      case 'Today':
        return DateTime(now.year, now.month, now.day);
      case 'Yesterday':
        return DateTime(now.year, now.month, now.day - 1);
      case 'This Week':
        return now.subtract(Duration(days: now.weekday % 7));
      case 'This Month':
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  DateTime? get _toDate {
    if (_filterRange == 'Yesterday') {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _service.list(from: _fromDate, to: _toDate, paymentMethod: _filterPayment, orderType: _filterOrderType);
      setState(() => _orders = orders);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load orders.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _orders.isEmpty
                        ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders found', subtitle: 'Try a different filter or date range.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _orders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _OrderTile(order: _orders[i], onChanged: _load),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: ['Today', 'Yesterday', 'This Week', 'This Month', 'All'].map((label) {
              final selected = _filterRange == label;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filterRange = label);
                    _load();
                  },
                  labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [null, 'CASH', 'UPI', 'CREDIT'].map((method) {
              final selected = _filterPayment == method;
              return Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: ChoiceChip(
                  label: Text(method ?? 'All Payments'),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filterPayment = method);
                    _load();
                  },
                  labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                  selectedColor: AppColors.textPrimary,
                  backgroundColor: AppColors.background,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [null, 'dine_in', 'takeaway', 'delivery'].map((type) {
              final selected = _filterOrderType == type;
              final label = type == null ? 'All Types' : (type == 'dine_in' ? 'Dine-In' : (type == 'takeaway' ? 'Takeaway' : 'Delivery'));
              return Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filterOrderType = type);
                    _load();
                  },
                  labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.background,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Order order;
  final VoidCallback onChanged;
  const _OrderTile({required this.order, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = order.paymentMethod == 'CASH'
        ? AppColors.cash
        : (order.paymentMethod == 'UPI' ? AppColors.upi : (order.paymentMethod == 'CREDIT' ? AppColors.credit : AppColors.info));

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)));
        onChanged();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('#${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (order.status == 'voided') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: const Text('VOIDED', style: TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(Formatters.dateTime(order.createdAt), style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    order.orderType == 'dine_in'
                        ? 'Dine-In${order.tableName != null ? ' · ${order.tableName}' : ''}${order.tableCustomerLabel != null ? ' · ${order.tableCustomerLabel}' : ''}'
                        : (order.orderType == 'delivery' ? 'Delivery' : 'Takeaway'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (order.staffName != null) Text('Attended by: ${order.staffName}', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Formatters.currency(order.grandTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(order.paymentMethod, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
