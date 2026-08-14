import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../services/upload_service.dart';

/// Reusable product-photo picker: shows the current image (existing or
/// newly picked), lets the user choose from gallery/camera, compresses and
/// resizes before upload (keeps things fast and keeps storage/API usage
/// small), and returns the uploaded relative URL via [onUploaded].
class ProductImagePicker extends StatefulWidget {
  final String? initialImageUrl;
  final ValueChanged<String> onUploaded;

  const ProductImagePicker({super.key, this.initialImageUrl, required this.onUploaded});

  @override
  State<ProductImagePicker> createState() => _ProductImagePickerState();
}

class _ProductImagePickerState extends State<ProductImagePicker> {
  String? _currentUrl;
  File? _localPreview;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialImageUrl;
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final compressedFile = await _compress(File(picked.path));
      setState(() => _localPreview = compressedFile);

      final url = await UploadService().uploadProductImage(compressedFile);
      setState(() => _currentUrl = url);
      widget.onUploaded(url);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not upload the image. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<File> _compress(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 80,
      minWidth: 800,
      minHeight: 800,
    );

    return result != null ? File(result.path) : file;
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Product Photo', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        InkWell(
          onTap: _uploading ? null : _showSourcePicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : _buildPreview(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildPreview() {
    if (_localPreview != null) {
      return Image.file(_localPreview!, fit: BoxFit.cover, width: double.infinity);
    }
    if (_currentUrl != null && _currentUrl!.isNotEmpty) {
      return Image.network(
        ApiConfig.resolveAssetUrl(_currentUrl!),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 32, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text('Tap to add a photo', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
