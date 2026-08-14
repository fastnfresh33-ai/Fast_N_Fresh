import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/product.dart';
import '../../services/inventory_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _service = InventoryService();
  List<Product> _products = [];
  bool _loading = true;
  String? _error;
  bool _lowStockOnly = false;

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
      final (products, _) = await _service.getInventory();
      setState(() => _products = products);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load inventory.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _adjustStock(Product product) async {
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    String type = 'STOCK_IN';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 16),
                Text('Adjust Stock — ${product.name}', style: Theme.of(context).textTheme.titleLarge),
                Text('Current stock: ${product.stock}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: ChoiceChip(label: const Text('Stock In'), selected: type == 'STOCK_IN', onSelected: (_) => setModalState(() => type = 'STOCK_IN'))),
                  const SizedBox(width: 8),
                  Expanded(child: ChoiceChip(label: const Text('Stock Out'), selected: type == 'STOCK_OUT', onSelected: (_) => setModalState(() => type = 'STOCK_OUT'))),
                  const SizedBox(width: 8),
                  Expanded(child: ChoiceChip(label: const Text('Adjust'), selected: type == 'ADJUSTMENT', onSelected: (_) => setModalState(() => type = 'ADJUSTMENT'))),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  decoration: InputDecoration(labelText: type == 'ADJUSTMENT' ? 'Quantity (+/-)' : 'Quantity'),
                ),
                const SizedBox(height: 12),
                TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason (optional)')),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () async {
                    final qty = int.tryParse(qtyController.text);
                    if (qty == null || qty == 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid quantity.')));
                      return;
                    }
                    try {
                      await _service.adjust(productId: product.id, type: type, quantity: qty, reason: reasonController.text.trim());
                      if (context.mounted) Navigator.pop(context, true);
                    } on ApiException catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  child: const Text('Save Adjustment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _lowStockOnly ? _products.where((p) => p.isLowStock).toList() : _products;

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              FilterChip(
                label: const Text('Low Stock Only'),
                selected: _lowStockOnly,
                onSelected: (v) => setState(() => _lowStockOnly = v),
                selectedColor: AppColors.warning,
                labelStyle: TextStyle(color: _lowStockOnly ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : displayed.isEmpty
                        ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'Nothing to show', subtitle: 'No products match this filter.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: displayed.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = displayed[i];
                                return InkWell(
                                  onTap: () => _adjustStock(p),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                            const SizedBox(height: 3),
                                            Text('Stock: ${p.stock}', style: Theme.of(context).textTheme.bodyMedium),
                                          ],
                                        ),
                                      ),
                                      if (p.isLowStock)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                                            SizedBox(width: 4),
                                            Text('Low Stock', style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                                          ]),
                                        ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
