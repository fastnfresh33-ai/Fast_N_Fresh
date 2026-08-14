import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/customer.dart';
import '../../providers/auth_provider.dart';
import '../../services/customer_service.dart';

import '../pos/add_customer_sheet.dart';
import 'customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _service = CustomerService();
  final _searchController = TextEditingController();

  Timer? _debounce;

  List<Customer> _customers = [];

  bool _loading = true;
  String? _error;
  bool _dueOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final customers = await _service.list(
        search: _searchController.text.trim(),
        hasDue: _dueOnly ? true : null,
      );

      if (!mounted) return;

      setState(() {
        _customers = customers;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load customers.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(
      const Duration(milliseconds: 400),
      _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canViewCreditHistory =
        context.watch<AuthProvider>().currentUser?.canViewCreditHistory ??
            false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
      ),

      // ---------------------------------------------------------------
      // ADD CUSTOMER
      // ---------------------------------------------------------------
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const AddCustomerSheet(),
          );

          if (result != null && mounted) {
            _load();
          }
        },
        child: const Icon(Icons.person_add_alt),
      ),

      body: Column(
        children: [
          // -----------------------------------------------------------
          // SEARCH
          // -----------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                ),
                isDense: true,
              ),
            ),
          ),

          // -----------------------------------------------------------
          // HAS DUE FILTER
          // ONLY ADMIN + MANAGER
          // -----------------------------------------------------------
          if (canViewCreditHistory)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Has Due'),
                    selected: _dueOnly,
                    onSelected: (value) {
                      setState(() {
                        _dueOnly = value;
                      });

                      _load();
                    },
                    labelStyle: TextStyle(
                      color: _dueOnly
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedColor: AppColors.credit,
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(
                        color: AppColors.border,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 6),

          // -----------------------------------------------------------
          // CUSTOMER LIST
          // -----------------------------------------------------------
          Expanded(
            child: _loading
                ? const LoadingState()
                : _error != null
                    ? ErrorState(
                        message: _error!,
                        onRetry: _load,
                      )
                    : _customers.isEmpty
                        ? const EmptyState(
                            icon: Icons.people_outline,
                            title: 'No customers yet',
                            subtitle:
                                'Add your first customer to get started.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _customers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final customer = _customers[index];

                                return _CustomerTile(
                                  customer: customer,
                                  onChanged: _load,
                                  canViewCreditHistory:
                                      canViewCreditHistory,
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

// =====================================================================
// CUSTOMER TILE
// =====================================================================

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onChanged;
  final bool canViewCreditHistory;

  const _CustomerTile({
    required this.customer,
    required this.onChanged,
    required this.canViewCreditHistory,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(
              customerId: customer.id,
            ),
          ),
        );

        if (context.mounted) {
          onChanged();
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            // ---------------------------------------------------------
            // CUSTOMER AVATAR
            // ---------------------------------------------------------
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                customer.name.isNotEmpty
                    ? customer.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ---------------------------------------------------------
            // CUSTOMER NAME + PHONE
            // ---------------------------------------------------------
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    customer.phone,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------
            // DUE
            // ONLY ADMIN + MANAGER
            // ---------------------------------------------------------
            if (canViewCreditHistory)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Due',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    Formatters.currency(
                      customer.outstandingBalance,
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: customer.hasDue
                          ? AppColors.credit
                          : AppColors.success,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}