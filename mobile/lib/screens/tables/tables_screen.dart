import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../models/table.dart';
import '../../services/table_service.dart';
import '../../providers/auth_provider.dart';
import 'table_detail_screen.dart';
import 'table_form_screen.dart';
import 'qr_management_screen.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  final TableService _service = TableService();

  List<CafeTable> _tables = [];
  bool _loading = true;
  String? _error;

  bool get _canManage {
    final user = context.read<AuthProvider>().currentUser;
    return user?.isAdmin ?? false;
  }

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final tables = await _service.list();

      if (!mounted) return;

      setState(() {
        _tables = tables;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load tables. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _addTable() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const TableFormScreen(),
      ),
    );

    if (result == true) {
      await _loadTables();
    }
  }

  Future<void> _openTable(CafeTable table) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TableDetailScreen(
          tableId: table.id,
        ),
      ),
    );

    if (mounted) {
      await _loadTables();
    }
  }

  Future<void> _editTable(CafeTable table) async {
    if (!_canManage) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TableFormScreen(
          table: table,
        ),
      ),
    );

    if (result == true) {
      await _loadTables();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tables'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'QR Management',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrManagementScreen()),
                );
                if (mounted) await _loadTables();
              },
              icon: const Icon(Icons.qr_code_2_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadTables,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _addTable,
              icon: const Icon(Icons.add),
              label: const Text('Add Table'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadTables,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _tables.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _tables.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.danger,
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Could not load tables',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _loadTables,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ),
        ],
      );
    }

    if (_tables.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.table_restaurant_outlined,
            size: 56,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'No tables found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Add your first table to start managing dine-in orders.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (_canManage) ...[
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: _addTable,
                icon: const Icon(Icons.add),
                label: const Text('Add Table'),
              ),
            ),
          ],
        ],
      );
    }

    return Stack(
      children: [
        GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: 150,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _tables.length,
          itemBuilder: (context, index) {
            final table = _tables[index];

            return _TableCard(
              table: table,
              canManage: _canManage,
              onChanged: _loadTables,
            );
          },
        ),

        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  final CafeTable table;
  final VoidCallback onChanged;
  final bool canManage;

  const _TableCard({
    required this.table,
    required this.onChanged,
    this.canManage = false,
  });

  Color get _statusColor {
    if (table.isOccupied) return AppColors.credit;
    if (table.isReserved) return AppColors.warning;
    return AppColors.success;
  }

  String get _statusLabel {
    if (table.isOccupied) {
      return 'Occupied • ${table.openOrderCount} Customer${table.openOrderCount > 1 ? 's' : ''}';
    }

    if (table.isReserved) return 'Reserved';

    return 'Available';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TableDetailScreen(
              tableId: table.id,
            ),
          ),
        );

        onChanged();
      },
      onLongPress: canManage
          ? () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => TableFormScreen(
                    table: table,
                  ),
                ),
              );

              if (saved == true) {
                onChanged();
              }
            }
          : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: table.isOccupied
                ? _statusColor.withValues(alpha: 0.4)
                : AppColors.border,
            width: table.isOccupied ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.table_restaurant_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                const Spacer(),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              table.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Seats ${table.capacity}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (table.hasQrNumber)
                  const Icon(Icons.qr_code_2, size: 14, color: AppColors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}