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

class _OrdersScreenState extends State<OrdersScreen>
    with WidgetsBindingObserver {
  final _service = OrderService();

  List<Order>? _orders;

  bool _isRefreshing = true;
  String? _error;

  Timer? _qrPollTimer;

  /*
   * Only today's NEW QR orders are tracked here.
   */
  final Set<String> _knownQrOrderIds = {};

  bool _hasSeededQrOrders = false;

  /*
   * Kitchen badge only counts today's unattended/open QR orders.
   */
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

    /*
     * Poll every 8 seconds so QR orders appear quickly.
     */
    _qrPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) {
        if (mounted) {
          _load(notifyNewQr: true);
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

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
    final wasBackgrounded =
        _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive ||
        _lastLifecycleState == AppLifecycleState.hidden;

    final returnedToForeground =
        state == AppLifecycleState.resumed && wasBackgrounded;

    _lastLifecycleState = state;

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

  /*
   * Returns true only when the order was created today.
   *
   * This is intentionally used only for NEW QR / kitchen queue logic.
   */
  bool _isCreatedToday(Order order) {
    final now = DateTime.now();
    final created = order.createdAt.toLocal();

    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }

  /*
   * A NEW QR order means:
   *
   * - QR order
   * - open
   * - unattended
   * - created today
   */
  bool _isNewQrOrder(Order order) {
    return order.isQrOrder &&
        order.status == 'open' &&
        order.staffName == null &&
        _isCreatedToday(order);
  }

  /*
   * Shows an app-wide popup for newly arrived QR orders.
   */
  void _showNewOrderPopup(List<Order> newOrders) {
    final navState = FastNFreshApp.navigatorKey.currentState;
    final popupContext = navState?.overlay?.context;

    if (popupContext == null) return;

    showDialog(
      context: popupContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            newOrders.length == 1
                ? 'New Order Received'
                : '${newOrders.length} New Orders Received',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: newOrders.take(5).map((order) {
                final itemsSummary = order.items
                    .map(
                      (item) => '${item.quantity}× ${item.name}',
                    )
                    .join(', ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.orderNumber}'
                        '${order.tableName != null ? ' · ${order.tableName}' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        itemsSummary,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                if (newOrders.length == 1) {
                  navState?.push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(
                        orderId: newOrders.first.id,
                      ),
                    ),
                  );
                } else {
                  navState?.push(
                    MaterialPageRoute(
                      builder: (_) => const KitchenScreen(),
                    ),
                  );
                }

                if (mounted) {
                  _load();
                }
              },
              child: const Text('View'),
            ),
          ],
        );
      },
    );
  }

  /*
   * Kitchen badge.
   *
   * IMPORTANT:
   * Only today's NEW/unattended QR orders are counted.
   */
  Future<void> _refreshKitchenBadge() async {
    try {
      final kitchenOrders = await _service.kitchenOrders();

      if (!mounted) return;

      final pendingToday = kitchenOrders.where((order) {
        return _isNewQrOrder(order);
      }).length;

      setState(() {
        _pendingKitchenCount = pendingToday;
      });
    } catch (_) {
      /*
       * Badge is only a convenience indicator.
       * Keep last known value on failure.
       */
    }
  }

  DateTime? get _fromDate {
    final now = DateTime.now();

    switch (_filterRange) {
      case 'Today':
        return DateTime(
          now.year,
          now.month,
          now.day,
        );

      case 'Yesterday':
        return DateTime(
          now.year,
          now.month,
          now.day - 1,
        );

      case 'This Week':
        return now.subtract(
          Duration(days: now.weekday % 7),
        );

      case 'This Month':
        return DateTime(
          now.year,
          now.month,
          1,
        );

      default:
        return null;
    }
  }

  DateTime? get _toDate {
    if (_filterRange == 'Yesterday') {
      final now = DateTime.now();

      return DateTime(
        now.year,
        now.month,
        now.day - 1,
        23,
        59,
        59,
      );
    }

    return null;
  }

  Future<void> _load({
    bool notifyNewQr = false,
  }) async {
    if (!mounted) return;

    setState(() {
      _isRefreshing = true;
    });

    /*
     * Kitchen badge is independent from Orders filters.
     */
    _refreshKitchenBadge();

    try {
      final orders = await _service.list(
        from: _fromDate,
        to: _toDate,
        paymentMethod: _filterPayment,
        orderType: _filterOrderType,
      );

      if (!mounted) return;

      /*
       * Only TODAY'S actual NEW QR orders participate in
       * notification / popup detection.
       */
      final currentQrOrders = orders.where(
        (order) => _isNewQrOrder(order),
      );

      final currentQrIds = currentQrOrders
          .map((order) => order.id)
          .toSet();

      final newQrOrderIds = _hasSeededQrOrders
          ? currentQrIds.difference(_knownQrOrderIds)
          : <String>{};

      /*
       * Update known IDs.
       */
      _knownQrOrderIds
        ..clear()
        ..addAll(currentQrIds);

      _hasSeededQrOrders = true;

      setState(() {
        _orders = orders;
        _error = null;
      });

      /*
       * Notify only genuinely new TODAY QR orders.
       */
      if (notifyNewQr &&
          newQrOrderIds.isNotEmpty &&
          mounted) {
        SystemSound.play(
          SystemSoundType.alert,
        );

        final newOrders = currentQrOrders
            .where(
              (order) => newQrOrderIds.contains(order.id),
            )
            .toList();

        if (newOrders.isNotEmpty) {
          _showNewOrderPopup(newOrders);

          final notificationBody =
              newOrders.length == 1
                  ? '#${newOrders.first.orderNumber} • '
                      '${newOrders.first.items.map(
                        (item) =>
                            '${item.quantity}x ${item.name}',
                      ).join(', ')}'
                  : '${newOrders.length} new QR orders are '
                      'waiting for confirmation.';

          NotificationService.instance
              .showNewOrderNotification(
            count: newOrders.length,
            bodyOverride: notificationBody,
          );
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      /*
       * Keep previous successful data on screen.
       */
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load orders.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            tooltip: _pendingKitchenCount > 0
                ? '$_pendingKitchenCount order'
                    '${_pendingKitchenCount == 1 ? '' : 's'} '
                    'awaiting confirmation'
                : 'Kitchen Display',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const KitchenScreen(),
                ),
              );

              _refreshKitchenBadge();
            },
            icon: Badge(
              isLabelVisible: _pendingKitchenCount > 0,
              label: Text(
                '$_pendingKitchenCount',
              ),
              backgroundColor: AppColors.warning,
              child: Icon(
                Icons.restaurant_menu_outlined,
                color: _pendingKitchenCount > 0
                    ? AppColors.warning
                    : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final orders = _orders;

    /*
     * Nothing loaded yet.
     */
    if (orders == null && _isRefreshing) {
      return LoadingState();
    }

    /*
     * First load failed.
     */
    if (orders == null && _error != null) {
      return ErrorState(
        message: _error!,
        onRetry: _load,
      );
    }

    if (orders == null) {
      return LoadingState();
    }

    /*
     * No orders.
     */
    if (orders.isEmpty) {
      return Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                0,
              ),
              child: InlineRetryBanner(
                message: 'Could not refresh. $_error',
                onRetry: _load,
              ),
            ),
          Expanded(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders found',
              subtitle:
                  'Try a different filter or date range.',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length +
            (_error != null ? 1 : 0),
        separatorBuilder: (_, __) =>
            const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (_error != null && index == 0) {
            return InlineRetryBanner(
              message:
                  'Could not refresh. Showing the last loaded orders.',
              onRetry: _load,
            );
          }

          final orderIndex =
              _error != null ? index - 1 : index;

          return _OrderTile(
            order: orders[orderIndex],
            onChanged: _load,
          );
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            children: [
              'Today',
              'Yesterday',
              'This Week',
              'This Month',
              'All',
            ].map((label) {
              final selected =
                  _filterRange == label;

              return Padding(
                padding:
                    const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _filterRange = label;
                    });

                    _load();
                  },
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor:
                      AppColors.primary,
                  backgroundColor:
                      AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(20),
                    side: BorderSide(
                      color: AppColors.border,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            children: [
              null,
              'CASH',
              'UPI',
              'CREDIT',
            ].map((method) {
              final selected =
                  _filterPayment == method;

              return Padding(
                padding:
                    const EdgeInsets.only(
                  right: 8,
                  bottom: 6,
                ),
                child: ChoiceChip(
                  label: Text(
                    method ?? 'All Payments',
                  ),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _filterPayment = method;
                    });

                    _load();
                  },
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                  selectedColor:
                      AppColors.textPrimary,
                  backgroundColor:
                      AppColors.background,
                  visualDensity:
                      VisualDensity.compact,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppColors.border,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            children: [
              null,
              'dine_in',
              'takeaway',
              'delivery',
            ].map((type) {
              final selected =
                  _filterOrderType == type;

              final label = type == null
                  ? 'All Types'
                  : type == 'dine_in'
                      ? 'Dine-In'
                      : type == 'takeaway'
                          ? 'Takeaway'
                          : 'Delivery';

              return Padding(
                padding:
                    const EdgeInsets.only(
                  right: 8,
                  bottom: 6,
                ),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _filterOrderType = type;
                    });

                    _load();
                  },
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                  selectedColor:
                      AppColors.primary,
                  backgroundColor:
                      AppColors.background,
                  visualDensity:
                      VisualDensity.compact,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppColors.border,
                    ),
                  ),
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

  const _OrderTile({
    required this.order,
    required this.onChanged,
  });

  /*
   * Only today's unattended QR open order gets NEW QR label.
   */
  bool _isNewQrOrder() {
    if (!order.isQrOrder ||
        order.status != 'open' ||
        order.staffName != null) {
      return false;
    }

    final now = DateTime.now();
    final created = order.createdAt.toLocal();

    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final paymentPending =
        order.paymentStatus == 'pending';

    final paymentColor =
        order.paymentStatus == 'paid'
            ? AppColors.success
            : ((order.paymentStatus == 'failed' ||
                    order.paymentStatus ==
                        'cancelled')
                ? AppColors.danger
                : AppColors.warning);

    final isNewQrOrder =
        _isNewQrOrder();

    /*
     * An ordinary old/open POS order should NOT look like
     * a NEW QR order.
     */
    final isOpenOrder =
        order.status == 'open';

    final statusColor = isNewQrOrder
        ? AppColors.warning
        : order.status == 'preparing'
            ? AppColors.info
            : order.status == 'ready'
                ? AppColors.success
                : AppColors.textMuted;

    final statusLabel = isNewQrOrder
        ? 'NEW'
        : order.status.toUpperCase();

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: order.id,
            ),
          ),
        );

        onChanged();
      },
      borderRadius:
          BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(14),

          /*
           * Amber border ONLY for today's NEW QR orders.
           */
          border: Border.all(
            color: isNewQrOrder
                ? AppColors.warning
                : AppColors.border,
            width:
                isNewQrOrder ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${order.orderNumber}',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),

                      /*
                       * QR badge remains visible for all QR orders.
                       * This does NOT mean NEW.
                       */
                      if (order.isQrOrder) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration:
                              BoxDecoration(
                            color: AppColors
                                .accent
                                .withValues(
                              alpha: 0.15,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(4),
                          ),
                          child: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_2,
                                size: 10,
                                color: AppColors
                                    .primaryDark,
                              ),
                              const SizedBox(
                                width: 2,
                              ),
                              Text(
                                'QR ORDER',
                                style:
                                    TextStyle(
                                  color: AppColors
                                      .primaryDark,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight
                                          .w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (order.status ==
                          'voided') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration:
                              BoxDecoration(
                            color: AppColors
                                .danger
                                .withValues(
                              alpha: 0.1,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(4),
                          ),
                          child: Text(
                            'VOIDED',
                            style: TextStyle(
                              color:
                                  AppColors.danger,
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 4),

                  Text(
                    Formatters.dateTime(
                      order.createdAt,
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),

                  Text(
                    order.orderType ==
                            'dine_in'
                        ? 'Dine-In'
                            '${order.tableName != null ? ' · ${order.tableName}' : ''}'
                            '${order.tableCustomerLabel != null ? ' · ${order.tableCustomerLabel}' : ''}'
                        : order.orderType ==
                                'delivery'
                            ? 'Delivery'
                            : 'Takeaway',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),

                  if (order.staffName != null)
                    Text(
                      'Attended by: ${order.staffName}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium,
                    )
                  else if (isNewQrOrder)
                    Text(
                      'Awaiting staff',
                      style: TextStyle(
                        color:
                            AppColors.textMuted,
                      ),
                    )
                  else if (order.isQrOrder &&
                      isOpenOrder)
                    Text(
                      'Unattended',
                      style: TextStyle(
                        color:
                            AppColors.textMuted,
                      ),
                    ),

                  if (order.qrCustomerContact
                              ?.name !=
                          null ||
                      order.qrCustomerContact
                              ?.phone !=
                          null)
                    Text(
                      [
                        order.qrCustomerContact
                            ?.name,
                        order.qrCustomerContact
                            ?.phone,
                      ]
                          .where(
                            (value) =>
                                value != null &&
                                value.isNotEmpty,
                          )
                          .join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium,
                    ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.currency(
                    order.grandTotal,
                  ),
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 4),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      /*
                       * STATUS
                       */
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration:
                            BoxDecoration(
                          color: statusColor
                              .withValues(
                            alpha: 0.12,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style:
                              TextStyle(
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w800,
                            color:
                                statusColor,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 4,
                      ),

                      /*
                       * PAYMENT STATUS
                       */
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration:
                            BoxDecoration(
                          color: paymentColor
                              .withValues(
                            alpha: 0.12,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(6),
                        ),
                        child: Text(
                          order.paymentStatus ==
                                  'paid'
                              ? '${order.paymentMethod} · PAID'
                              : paymentPending
                                  ? '${order.paymentMethod} · PENDING'
                                  : '${order.paymentMethod} · ${order.paymentStatus.toUpperCase()}',
                          style:
                              TextStyle(
                            color:
                                paymentColor,
                            fontSize: 9.5,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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