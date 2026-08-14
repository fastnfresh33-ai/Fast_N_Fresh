import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/table.dart';
import '../../models/order.dart';
import '../../services/table_service.dart';
import '../../providers/cart_provider.dart';
import '../pos/pos_screen.dart';

/// Shows every currently-open unpaid customer/order on this table.
///
/// Each customer/order remains completely separate:
/// - Separate cart
/// - Separate order
/// - Separate bill
/// - Separate payment
///
/// This allows multiple simultaneous customers on one table.
class TableDetailScreen extends StatefulWidget {
  final String tableId;

  const TableDetailScreen({
    super.key,
    required this.tableId,
  });

  @override
  State<TableDetailScreen> createState() => _TableDetailScreenState();
}

class _TableDetailScreenState extends State<TableDetailScreen> {
  final TableService _service = TableService();

  CafeTable? _table;
  List<Order> _openOrders = [];

  bool _loading = true;
  bool _starting = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.getDetail(widget.tableId);

      if (!mounted) return;

      setState(() {
        _table = result.$1;
        _openOrders = result.$2;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load this table.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addCustomer() async {
    if (_starting) return;

    setState(() {
      _starting = true;
    });

    try {
      final order = await _service.startOrder(
        widget.tableId,
        tableCustomerLabel:
            'Customer ${_openOrders.length + 1}',
      );

      if (!mounted) return;

      // Start with a fresh cart for this customer.
      context.read<CartProvider>().clear();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PosScreen(
            orderType: 'dine_in',
            tableId: widget.tableId,
            tableName: _table?.name,
            tableCustomerLabel: order.tableCustomerLabel,
            openOrderId: order.id,
          ),
        ),
      );

      if (mounted) {
        await _load();
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start a new customer order.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  Future<void> _openExisting(
    Order order, {
    bool autoOpenCart = false,
  }) async {
    context.read<CartProvider>().clear();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PosScreen(
          orderType: 'dine_in',
          tableId: widget.tableId,
          tableName: _table?.name,
          tableCustomerLabel: order.tableCustomerLabel,
          openOrderId: order.id,
          autoOpenCart: autoOpenCart,
        ),
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _table?.name ?? 'Table',
        ),
      ),
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_openOrders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 40,
                          ),
                          child: Center(
                            child: Text(
                              'This table is empty.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._openOrders.map(
                          (order) => _CustomerOrderCard(
                            order: order,
                            onOpen: () => _openExisting(order),
                            onBill: () => _openExisting(
                              order,
                              autoOpenCart: true,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      OutlinedButton.icon(
                        onPressed:
                            _starting ? null : _addCustomer,
                        icon: _starting
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.person_add_alt,
                                size: 18,
                              ),
                        label: const Text(
                          'Add Customer',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onOpen;
  final VoidCallback onBill;

  const _CustomerOrderCard({
    required this.order,
    required this.onOpen,
    required this.onBill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.tableCustomerLabel ??
                      'Customer',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                Formatters.currency(
                  order.grandTotal,
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          Text(
            order.items.isEmpty
                ? 'No items yet'
                : order.items
                    .map(
                      (item) =>
                          '${item.quantity}x ${item.name}',
                    )
                    .join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                Theme.of(context).textTheme.bodyMedium,
          ),

          if (order.staffName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Attended by: ${order.staffName}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: const Text(
                    'Open Order',
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: ElevatedButton(
                  onPressed: onBill,
                  child: const Text(
                    'Bill',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}