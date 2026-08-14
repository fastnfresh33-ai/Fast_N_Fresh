import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/dashboard_models.dart';
import '../../services/dashboard_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/stat_card.dart';
import '../orders/order_detail_screen.dart';
import '../../services/order_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _dashboardService = DashboardService();

  bool _loading = true;
  String? _error;
  DashboardData? _data;
  SalesOverview? _overview;
  String _overviewTab = 'Today';

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
      final results = await Future.wait([
        _dashboardService.getDashboard(),
        _dashboardService.getSalesOverview(),
      ]);

      _data = results[0] as DashboardData;
      _overview = results[1] as SalesOverview;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load the dashboard.';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName =
        context.watch<AuthProvider>().currentUser?.name ?? 'Admin';

    final hour = DateTime.now().hour;

    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return Scaffold(
      appBar: AppBar(
        title: const Text('FAST N FRESH CAFE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
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
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      24,
                    ),
                    children: [
                      Text(
                        '$greeting, $userName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),

                      const SizedBox(height: 16),

                      _buildStatsGrid(),

                      const SizedBox(height: 20),

                      _buildAlerts(),

                      const SizedBox(height: 20),

                      _buildSalesOverview(),

                      const SizedBox(height: 20),

                      _buildRecentOrders(),

                      const SizedBox(height: 20),

                      _buildTopProducts(),
                    ],
                  ),
                ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------------

  Widget _buildStatsGrid() {
    final d = _data!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final isVerySmallPhone = width < 340;
        final isSmallPhone = width >= 340 && width < 390;

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),

          crossAxisSpacing: 12,
          mainAxisSpacing: 12,

          // More vertical space on smaller screens.
          childAspectRatio: isVerySmallPhone
              ? 1.05
              : isSmallPhone
                  ? 1.15
                  : 1.40,

          children: [
            StatCard(
              label: "Today's Sales",
              value: Formatters.currency(d.today.sales),
              icon: Icons.payments_outlined,
              accentColor: AppColors.primary,
            ),

            StatCard(
              label: 'Orders',
              value: '${d.today.orders}',
              icon: Icons.receipt_long_outlined,
              accentColor: AppColors.info,
            ),

            StatCard(
              label: 'UDHAR / Credit',
              value: Formatters.currency(d.today.credit),
              icon: Icons.account_balance_wallet_outlined,
              accentColor: AppColors.credit,
            ),

            StatCard(
              label: 'Low Stock',
              value: '${d.lowStockCount} Items',
              icon: Icons.inventory_2_outlined,
              accentColor: AppColors.warning,
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ALERTS
  // ---------------------------------------------------------------------------

  Widget _buildAlerts() {
    final d = _data!;

    final alerts = <Widget>[];

    if (d.lowStockCount > 0) {
      alerts.add(
        _alertTile(
          Icons.warning_amber_rounded,
          AppColors.warning,
          '${d.lowStockCount} products are low on stock',
        ),
      );
    }

    if (d.outstandingCreditTotal > 0) {
      alerts.add(
        _alertTile(
          Icons.account_balance_wallet_outlined,
          AppColors.credit,
          '${Formatters.currency(d.outstandingCreditTotal)} outstanding from ${d.outstandingCreditCustomerCount} customers',
        ),
      );
    }

    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alerts',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        ...alerts,
      ],
    );
  }

  Widget _alertTile(
    IconData icon,
    Color color,
    String text,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.95),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SALES OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _buildSalesOverview() {
    final o = _overview!;

    final tabs = {
      'Today': o.today,
      'Yesterday': o.yesterday,
      'This Week': o.thisWeek,
      'This Month': o.thisMonth,
    };

    final selected = tabs[_overviewTab]!;

    return Container(
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
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Sales Overview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),

              const SizedBox(width: 10),

              Flexible(
                child: Text(
                  Formatters.currency(selected.sales),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Tabs
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tabs.keys.map((label) {
              final isSelected = _overviewTab == label;

              return ChoiceChip(
                label: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _overviewTab = label;
                  });
                },
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(
                    color: AppColors.border,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 160,
            child: o.last14Days.isEmpty
                ? const Center(
                    child: Text(
                      'No sales data yet',
                      style: TextStyle(
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(
                        show: false,
                      ),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: false,
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (
                              int i = 0;
                              i < o.last14Days.length;
                              i++
                            )
                              FlSpot(
                                i.toDouble(),
                                o.last14Days[i].sales,
                              ),
                          ],
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          dotData: const FlDotData(
                            show: false,
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 8),

          // Payment summary
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 350;

              if (isSmall) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash ${Formatters.currency(selected.cash)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'UPI ${Formatters.currency(selected.upi)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Credit ${Formatters.currency(selected.credit)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
              }

              return Text(
                'Cash ${Formatters.currency(selected.cash)}   ·   '
                'UPI ${Formatters.currency(selected.upi)}   ·   '
                'Credit ${Formatters.currency(selected.credit)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RECENT ORDERS
  // ---------------------------------------------------------------------------

  Widget _buildRecentOrders() {
    final orders = _data!.recentOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Orders',
          style: Theme.of(context).textTheme.titleMedium,
        ),

        const SizedBox(height: 10),

        if (orders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No orders yet today.',
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          ...orders.map(
            (o) => _recentOrderTile(o),
          ),
      ],
    );
  }

  Widget _recentOrderTile(
    RecentOrderSummary o,
  ) {
    final color = o.paymentMethod == 'CASH'
        ? AppColors.cash
        : (o.paymentMethod == 'UPI'
            ? AppColors.upi
            : AppColors.credit);

    return InkWell(
      onTap: () => _openOrder(o.orderNumber),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Order info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${o.orderNumber}  ${o.itemsSummary}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    Formatters.relative(o.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Amount + payment
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency(o.grandTotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      o.paymentMethod,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OPEN ORDER
  // ---------------------------------------------------------------------------

  Future<void> _openOrder(int orderNumber) async {
    try {
      final orders = await OrderService().list(
        search: orderNumber.toString(),
      );

      if (orders.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: orders.first.id,
            ),
          ),
        );
      }
    } catch (_) {
      // Non-critical navigation helper.
    }
  }

  // ---------------------------------------------------------------------------
  // TOP PRODUCTS
  // ---------------------------------------------------------------------------

  Widget _buildTopProducts() {
    final products = _data!.topSellingProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Selling Products',
          style: Theme.of(context).textTheme.titleMedium,
        ),

        const SizedBox(height: 10),

        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No sales data yet.',
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: Column(
              children: products.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Flexible(
                        child: Text(
                          '${p.quantitySold} sold',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}