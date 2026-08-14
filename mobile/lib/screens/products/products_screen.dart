import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_config.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/product.dart';
import '../../models/category.dart';
import '../../services/catalog_service.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _productService = ProductService();
  final _categoryService = CategoryService();
  final _searchController = TextEditingController();

  List<Product> _products = [];
  List<Category> _categories = [];
  bool _loading = true;
  String? _error;

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
      final results = await Future.wait([_productService.list(search: _searchController.text.trim()), _categoryService.list()]);
      setState(() {
        _products = results[0] as List<Product>;
        _categories = results[1] as List<Category>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load products.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Product? product}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product, categories: _categories)),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _productService.delete(product.id);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton(onPressed: () => _openForm(), child: const Icon(Icons.add)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search products…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: IconButton(icon: const Icon(Icons.search, size: 18), onPressed: _load),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _products.isEmpty
                        ? const EmptyState(icon: Icons.fastfood_outlined, title: 'No products yet', subtitle: 'Tap + to add your first product.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: _products.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = _products[i];
                                return _ProductTile(product: p, onTap: () => _openForm(product: p), onDelete: () => _deleteProduct(p));
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ProductTile({required this.product, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.hasImage
                ? Image.network(
                    ApiConfig.resolveAssetUrl(product.imageUrl),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  if (!product.isAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.textMuted.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: const Text('Unavailable', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(product.categoryName ?? '', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Row(children: [
                  Text(Formatters.currency(product.sellingPrice), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  if (product.trackInventory) ...[
                    const SizedBox(width: 10),
                    Text('Stock: ${product.stock}', style: TextStyle(fontSize: 12, color: product.isLowStock ? AppColors.warning : AppColors.textMuted, fontWeight: product.isLowStock ? FontWeight.w700 : FontWeight.w400)),
                  ],
                ]),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20), onPressed: onDelete),
        ]),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 52,
      height: 52,
      color: AppColors.background,
      child: const Icon(Icons.fastfood_outlined, color: AppColors.textMuted, size: 22),
    );
  }
}
