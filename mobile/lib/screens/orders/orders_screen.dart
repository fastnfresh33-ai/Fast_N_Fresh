import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/order.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import 'order_detail_screen.dart';
import 'kitchen_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with WidgetsBindingObserver {
  final _service = OrderService();

  // `null` means "no data loaded yet" (or the last load failed before ever
  // succeeding). A non-null list -- even an empty one -- means we have real
  // data to show, so a later failed refresh never blanks the screen: the
  // last successful results just stay on screen with a small inline
  // "couldn't refresh" banner instead of being replaced by an error page.
  List<Order>? _orders;

  bool _isRefreshing = true;
  String? _error;
  Timer? _qrPollTimer;
  final Set<String> _knownQrOrderIds = {};
  bool _hasSeededQrOrders = false;

  // Drives the Kitchen Display badge in the AppBar: amber while there's
  // at least one order in the kitchen queue still awaiting confirmation
  // (status 'open' -- NEW). Red is reserved for actual failures/cancellations.
  int _pendingKitchenCount = 0;

  String _filterRange = 'Today';
  String? _filterPayment;
  String? _filterOrderType;

  AppLifecycleState? _lastLifecycleState;
  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshKitchenBadge();
    _qrPollTimer = Timer.periodic(Duration(seconds: 8), (_) {
      if (mounted) _load(notifyNewQr: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Re-fetch the list automatically once the device regains network
    // connectivity, if the previous attempt had failed. Reading the
    // provider here (rather than only in initState) is what
    // `didChangeDependencies` is for, and it's safe to re-subscribe since
    // we guard with reference equality below.
    final connectivity = context.read<ConnectivityProvider>();
    if (!identical(connectivity, _connectivity)) {
      _connectivity?.removeListener(_handleConnectivityChange);
      _connectivity = connectivity;
      _wasOnline = connectivity.isOnline;
      _connectivity!.addListener(_handleConnectivityChange);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_handleConnectivityChange);
    _qrPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground = state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

    // Only worth an automatic refresh if the last attempt actually failed;
    // otherwise the data on screen is already fine.
    if (returnedToForeground && _error != null && mounted) {
      _load();
    }
  }

  void _handleConnectivityChange() {
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline && !_wasOnline && _error != null) {
      _load();
    }

    _wasOnline = isOnline;
  }

  /// Shows an on-top pop-up dialog for one or more newly-arrived QR orders,
  /// visible no matter which tab/screen is currently on screen. Uses the
  /// app-wide navigator (see [FastNFreshApp.navigatorKey]) instead of this
  /// screen's own context, since this screen may be backgrounded inside
  /// MainShell's IndexedStack when the alert fires.
  void _showNewOrderPopup(List<Order> newOrders) {
    final navState = FastNFreshApp.navigatorKey.currentState;
    final popupContext = navState?.overlay?.context;
    if (popupContext == null) return;

    showDialog(
      context: popupContext,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(newOrders.length == 1 ? 'New Order Received' : '${newOrders.length} New Orders Received'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: newOrders.take(5).map((o) {
              final itemsSummary = o.items.map((i) => '${i.quantity}× ${i.name}').join(', ');
              return Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${o.orderNumber}${o.tableName != null ? ' · ${o.tableName}' : ''}',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(itemsSummary, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (newOrders.length == 1) {
                navState?.push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: newOrders.first.id)));
              } else {
                navState?.push(MaterialPageRoute(builder: (_) => KitchenScreen()));
              }
              if (mounted) _load();
            },
            child: Text('View'),
          ),
        ],
      ),
    );
  }

  /// Refreshes the Kitchen Display badge count/color shown on the AppBar
  /// icon. Counts NEW orders in the kitchen queue. Amber is used for the
  /// actionable queue count; red remains reserved for failure/cancellation.
  Future<void> _refreshKitchenBadge() async {
    try {
      final kitchenOrders = await _service.kitchenOrders();
      if (!mounted) return;
      setState(() {
        _pendingKitchenCount = kitchenOrders.where((o) => o.status == 'open').length;
      });
    } catch (_) {
      // Badge is a convenience indicator, not critical data -- silently
      // keep showing the last known count rather than surfacing an error.
    }
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

  Future<void> _load({bool notifyNewQr = false}) async {
    setState(() {
      _isRefreshing = true;
    });

    // Kitchen Display badge/color is independent of this screen's own
    // date/payment/type filters -- it always reflects the live kitchen
    // queue, so it's refreshed from its own dedicated endpoint alongside
    // every poll tick rather than derived from the (possibly filtered)
    // `_orders` list above.
    _refreshKitchenBadge();

    try {
      final orders = await _service.list(
        from: _fromDate,
        to: _toDate,
        paymentMethod: _filterPayment,
        orderType: _filterOrderType,
      );

      if (!mounted) return;

      final currentQrIds = orders.where((o) => o.isQrOrder && o.status == 'open').map((o) => o.id).toSet();
      final newQrOrders = _hasSeededQrOrders ? currentQrIds.difference(_knownQrOrderIds) : <String>{};
      _knownQrOrderIds
        ..clear()
        ..addAll(currentQrIds);
      _hasSeededQrOrders = true;

      setState(() {
        _orders = orders;
        _error = null;
      });

      if (notifyNewQr && newQrOrders.isNotEmpty && mounted) {
        SystemSound.play(SystemSoundType.alert);

        // This poll keeps running even while another tab is on screen
        // (this screen stays mounted in MainShell's IndexedStack), but a
        // SnackBar tied to THIS screen's own Scaffold only paints while the
        // Orders tab is the one actually visible -- IndexedStack keeps every
        // tab alive but only paints the active one, so a SnackBar posted
        // from a backgrounded tab was silently invisible. Using the
        // app-wide navigatorKey instead shows a real pop-up dialog on top
        // of whatever tab/screen the admin/manager/staff user is currently
        // looking at.
        final newOrders = orders.where((o) => newQrOrders.contains(o.id)).toList();
        _showNewOrderPopup(newOrders);

        // Also surface a system notification -- this is what lets staff
        // notice a new order even if the app is backgrounded (not killed).
        final notificationBody = newOrders.length == 1
            ? '#${newOrders.first.orderNumber} • ${newOrders.first.items.map((i) => '${i.quantity}x ${i.name}').join(', ')}'
            : '${newOrders.length} new QR orders are waiting for confirmation.';
        NotificationService.instance.showNewOrderNotification(
          count: newQrOrders.length,
          bodyOverride: notificationBody,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // Deliberately NOT clearing `_orders` here -- if we already had a
      // successful list on screen, it stays visible with a small inline
      // retry banner instead of being replaced by a full error page.
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load orders.');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Orders'),
        actions: [
          IconButton(
            tooltip: _pendingKitchenCount > 0
                ? '$_pendingKitchenCount order${_pendingKitchenCount == 1 ? '' : 's'} awaiting confirmation'
                : 'Kitchen Display',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => KitchenScreen()));
              _refreshKitchenBadge();
            },
            icon: Badge(
              isLabelVisible: _pendingKitchenCount > 0,
              label: Text('$_pendingKitchenCount'),
              backgroundColor: AppColors.warning,
              child: Icon(
                Icons.restaurant_menu_outlined,
                // Amber while NEW orders are waiting; neutral when the queue is clear.
                color: _pendingKitchenCount > 0 ? AppColors.warning : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final orders = _orders;

    // Nothing cached yet and a load is in flight -> full skeleton.
    if (orders == null && _isRefreshing) {
      return LoadingState();
    }

    // Nothing cached and the load failed -> only now show the full-screen
    // error state with "Try Again" (last-resort fallback, as required).
    if (orders == null && _error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    if (orders == null) {
      // Defensive fallback; shouldn't normally be reached.
      return LoadingState();
    }

    if (orders.isEmpty) {
      return Column(
        children: [
          if (_error != null)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineRetryBanner(
                message: 'Could not refresh. $_error',
                onRetry: _load,
              ),
            ),
          Expanded(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders found',
              subtitle: 'Try a different filter or date range.',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.all(16),
        itemCount: orders.length + (_error != null ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (_error != null && i == 0) {
            return InlineRetryBanner(
              message: 'Could not refresh. Showing the last loaded orders.',
              onRetry: _load,
            );
          }
          final orderIndex = _error != null ? i - 1 : i;
          return _OrderTile(order: orders[orderIndex], onChanged: _load);
        },
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
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: ['Today', 'Yesterday', 'This Week', 'This Month', 'All'].map((label) {
              final selected = _filterRange == label;
              return Padding(
                padding: EdgeInsets.only(right: 8),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.border)),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            children: [null, 'CASH', 'UPI', 'CREDIT'].map((method) {
              final selected = _filterPayment == method;
              return Padding(
                padding: EdgeInsets.only(right: 8, bottom: 6),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.border)),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            children: [null, 'dine_in', 'takeaway', 'delivery'].map((type) {
              final selected = _filterOrderType == type;
              final label = type == null ? 'All Types' : (type == 'dine_in' ? 'Dine-In' : (type == 'takeaway' ? 'Takeaway' : 'Delivery'));
              return Padding(
                padding: EdgeInsets.only(right: 8, bottom: 6),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.border)),
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
  _OrderTile({required this.order, required this.onChanged});

  String _qrStatusLabel(String status) {
    switch (status) {
      case 'preparing':
        return 'PREPARING';
      case 'ready':
        return 'READY';
      default:
        return 'NEW QR ORDER';
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentPending = order.paymentStatus == 'pending';
    final paymentColor = order.paymentStatus == 'paid'
        ? AppColors.success
        : ((order.paymentStatus == 'failed' || order.paymentStatus == 'cancelled') ? AppColors.danger : AppColors.warning);

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)));
        onChanged();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: order.status == 'open' ? AppColors.warning : AppColors.border, width: order.status == 'open' ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('#${order.orderNumber}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (order.isQrOrder) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_2, size: 10, color: AppColors.primaryDark),
                            SizedBox(width: 2),
                            Text('QR ORDER', style: TextStyle(color: AppColors.primaryDark, fontSize: 9, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                    if (order.status == 'voided') ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('VOIDED', style: TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  SizedBox(height: 4),
                  Text(Formatters.dateTime(order.createdAt), style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    order.orderType == 'dine_in'
                        ? 'Dine-In${order.tableName != null ? ' · ${order.tableName}' : ''}${order.tableCustomerLabel != null ? ' · ${order.tableCustomerLabel}' : ''}'
                        : (order.orderType == 'delivery' ? 'Delivery' : 'Takeaway'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (order.staffName != null) Text('Attended by: ${order.staffName}', style: Theme.of(context).textTheme.bodyMedium)
                  else if (order.isQrOrder) Text('Awaiting staff', style: TextStyle(color: AppColors.textMuted)),
                  if (order.qrCustomerContact?.name != null || order.qrCustomerContact?.phone != null)
                    Text(
                      [order.qrCustomerContact?.name, order.qrCustomerContact?.phone].where((s) => s != null && s.isNotEmpty).join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Formatters.currency(order.grandTotal), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (order.status == 'open' ? AppColors.warning : (order.status == 'preparing' ? AppColors.info : (order.status == 'ready' ? AppColors.success : AppColors.textMuted))).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.status == 'open' ? 'NEW' : order.status.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: order.status == 'open' ? AppColors.warning : (order.status == 'preparing' ? AppColors.info : (order.status == 'ready' ? AppColors.success : AppColors.textMuted))),
                      ),
                    ),
                    SizedBox(height: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: paymentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        order.paymentStatus == 'paid' ? '${order.paymentMethod} · PAID' : (paymentPending ? '${order.paymentMethod} · PENDING' : '${order.paymentMethod} · ${order.paymentStatus.toUpperCase()}'),
                        style: TextStyle(color: paymentColor, fontSize: 9.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
