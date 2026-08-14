import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../models/customer.dart';
import '../../services/customer_service.dart';
import 'add_customer_sheet.dart';

class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({super.key});

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _service = CustomerService();
  final _searchController = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    try {
      final results = await _service.list(search: search);
      setState(() {
        _customers = results;
        _error = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(children: [
                  Text('Select Customer', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(hintText: 'Search by name or phone…', prefixIcon: Icon(Icons.search, size: 20), isDense: true),
                  onSubmitted: (v) => _load(search: v),
                  onChanged: (v) {
                    if (v.isEmpty) _load();
                  },
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final newCustomer = await showModalBottomSheet<Customer>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const AddCustomerSheet(),
                    );
                    if (newCustomer != null && mounted) Navigator.pop(context, newCustomer);
                  },
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Add New Customer'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _customers.isEmpty
                            ? const Center(child: Text('No customers found', style: TextStyle(color: AppColors.textMuted)))
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _customers.length,
                                itemBuilder: (context, i) {
                                  final c = _customers[i];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryLight,
                                      child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                    ),
                                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(c.phone),
                                    trailing: c.hasDue
                                        ? Text('Due ${Formatters.currency(c.outstandingBalance)}', style: const TextStyle(color: AppColors.credit, fontWeight: FontWeight.w700, fontSize: 12))
                                        : null,
                                    onTap: () => Navigator.pop(context, c),
                                  );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}
