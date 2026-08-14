import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import 'cart_sheet.dart';

class PosScreen extends StatefulWidget {
  final String? orderType;
  final String? tableId;
  final String? tableName;
  final String? tableCustomerLabel;
  final String? openOrderId;

  /// If true, the cart sheet will open automatically
  /// after the POS screen is displayed.
  final bool autoOpenCart;

  const PosScreen({
    super.key,
    this.orderType,
    this.tableId,
    this.tableName,
    this.tableCustomerLabel,
    this.openOrderId,
    this.autoOpenCart = false,
  });

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String? _selectedCategoryId;

  final TextEditingController _searchController =
      TextEditingController();

  String get _searchQuery =>
      _searchController.text.trim().toLowerCase();

  String get _resolvedOrderType {
    if (widget.orderType != null &&
        widget.orderType!.trim().isNotEmpty) {
      return widget.orderType!;
    }

    if (widget.tableId != null) {
      return 'dine_in';
    }

    return 'takeaway';
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final catalog = context.read<CatalogProvider>();

      if (catalog.products.isEmpty && !catalog.isLoading) {
        catalog.load();
      }

      context.read<CartProvider>().configureContext(
            orderType: _resolvedOrderType,
            tableId: widget.tableId,
            tableName: widget.tableName,
            tableCustomerLabel: widget.tableCustomerLabel,
            openOrderId: widget.openOrderId,
          );

      if (widget.autoOpenCart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openCart();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filteredProducts(
    CatalogProvider catalog,
  ) {
    var products =
        catalog.productsForCategory(_selectedCategoryId);

    if (_searchQuery.isNotEmpty) {
      products = products.where((product) {
        return product.name
            .toLowerCase()
            .contains(_searchQuery);
      }).toList();
    }

    return products;
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tableName != null
              ? 'POS • ${widget.tableName}'
              : 'Point of Sale',
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Cart',
                onPressed: _openCart,
                icon: const Icon(
                  Icons.shopping_cart_outlined,
                ),
              ),

              if (cart.itemCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${cart.itemCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          if (widget.tableId != null)
            _buildTableBanner(),

          _buildSearch(),

          _buildCategories(catalog),

          Expanded(
            child: _buildProducts(catalog),
          ),
        ],
      ),

      bottomNavigationBar: cart.itemCount > 0
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12,
              ),
              child: ElevatedButton(
                onPressed: _openCart,
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.shopping_cart_outlined,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View Cart • '
                      '${Formatters.currency(cart.grandTotal)}',
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTableBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.table_restaurant_outlined,
            color: AppColors.primary,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tableName ??
                      'Dine-In Table',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),

                if (widget.tableCustomerLabel != null &&
                    widget.tableCustomerLabel!
                        .trim()
                        .isNotEmpty)
                  Text(
                    widget.tableCustomerLabel!,
                    style: const TextStyle(
                      color:
                          AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),

                if (widget.openOrderId != null)
                  const Text(
                    'Existing open order',
                    style: TextStyle(
                      color: AppColors.credit,
                      fontSize: 12,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        8,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) {
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search products...',
          prefixIcon: const Icon(
            Icons.search,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();

                        setState(() {});
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                    )
                  : null,
        ),
      ),
    );
  }

  Widget _buildCategories(
    CatalogProvider catalog,
  ) {
    if (catalog.categories.isEmpty) {
      return const SizedBox(height: 4);
    }

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
        ),
        scrollDirection: Axis.horizontal,
        itemCount:
            catalog.categories.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _categoryChip(
              label: 'All',
              selected:
                  _selectedCategoryId == null,
              onTap: () {
                setState(() {
                  _selectedCategoryId = null;
                });
              },
            );
          }

          final category =
              catalog.categories[index - 1];

          return _categoryChip(
            label: category.name,
            selected:
                _selectedCategoryId ==
                    category.id,
            onTap: () {
              setState(() {
                _selectedCategoryId =
                    category.id;
              });
            },
          );
        },
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor:
          AppColors.primaryLight,
      labelStyle: TextStyle(
        color: selected
            ? AppColors.primary
            : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.primary
            : AppColors.border,
      ),
    );
  }

  Widget _buildProducts(
    CatalogProvider catalog,
  ) {
    if (catalog.isLoading &&
        catalog.products.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (catalog.errorMessage != null &&
        catalog.products.isEmpty) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),

          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.danger,
          ),

          const SizedBox(height: 16),

          const Center(
            child: Text(
              'Could not load products',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Center(
            child: Text(
              catalog.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Center(
            child: ElevatedButton.icon(
              onPressed: catalog.load,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ),
        ],
      );
    }

    final products =
        _filteredProducts(catalog);

    if (products.isEmpty) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),

          const Icon(
            Icons.fastfood_outlined,
            size: 52,
            color: AppColors.textMuted,
          ),

          const SizedBox(height: 16),

          const Center(
            child: Text(
              'No products found',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 8),

          const Center(
            child: Text(
              'Try another search or category.',
              style: TextStyle(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding:
              const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            20,
          ),
          gridDelegate:
              const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 190,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            return _ProductCard(
              product: products[index],
            );
          },
        ),

        if (catalog.isLoading)
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

class _ProductCard extends StatelessWidget {
  final Product product;

  const _ProductCard({
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final cart =
        context.watch<CartProvider>();

    final qtyInCart = cart.items
        .where(
          (i) => i.product.id == product.id,
        )
        .fold(
          0,
          (sum, item) =>
              sum + item.quantity,
        );

    final outOfStock =
        product.trackInventory &&
            product.stock <= 0;

    return InkWell(
      onTap: outOfStock
          ? null
          : () {
              context
                  .read<CartProvider>()
                  .addProduct(product);

              ScaffoldMessenger.of(
                context,
              )
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      '${product.name} added to cart',
                    ),
                    duration:
                        const Duration(
                      milliseconds: 700,
                    ),
                  ),
                );
            },
      borderRadius:
          BorderRadius.circular(14),
      child: Container(
        padding:
            const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: outOfStock
              ? AppColors.background
              : AppColors.surface,
          borderRadius:
              BorderRadius.circular(14),
          border: Border.all(
            color: qtyInCart > 0
                ? AppColors.primary
                : AppColors.border,
            width:
                qtyInCart > 0 ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (product.hasImage) ...[
              Container(
                height: 72,
                width: double.infinity,
                decoration:
                    BoxDecoration(
                  color:
                      AppColors.background,
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                clipBehavior:
                    Clip.antiAlias,
                child: Image.network(
                  ApiConfig
                      .resolveAssetUrl(
                    product.imageUrl,
                  ),
                  fit: BoxFit.contain,
                  errorBuilder:
                      (_, __, ___) {
                    return const Icon(
                      Icons
                          .fastfood_outlined,
                      size: 30,
                      color: AppColors
                          .textSecondary,
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),
            ],

            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),

                if (qtyInCart > 0) ...[
                  const SizedBox(width: 6),

                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          AppColors.primary,
                      borderRadius:
                          BorderRadius
                              .circular(
                        20,
                      ),
                    ),
                    child: Text(
                      '$qtyInCart',
                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const Spacer(),

            if (outOfStock)
              const Text(
                'Out of stock',
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      AppColors.danger,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w600,
                ),
              )
            else if (product.isLowStock)
              Text(
                '${product.stock} left',
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      AppColors.warning,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

            const SizedBox(height: 2),

            Text(
              Formatters.currency(
                product.sellingPrice,
              ),
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color:
                    AppColors.primary,
                fontWeight:
                    FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}