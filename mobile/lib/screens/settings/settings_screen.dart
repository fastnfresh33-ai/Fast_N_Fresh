import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/misc_models.dart';
import '../../services/misc_services.dart';
import '../../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService();
  BusinessSettings? _settings;
  bool _loading = true;
  String? _error;

  late TextEditingController _cafeNameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _gstController;
  late TextEditingController _upiController;
  late TextEditingController _footerController;
  late TextEditingController _taxPercentController;
  late TextEditingController _defaultDiscountController;
  bool _taxEnabled = false;

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
      final settings = await _service.get();
      setState(() {
        _settings = settings;
        _cafeNameController = TextEditingController(text: settings.cafeName);
        _phoneController = TextEditingController(text: settings.phone);
        _addressController = TextEditingController(text: settings.address);
        _gstController = TextEditingController(text: settings.gstNumber);
        _upiController = TextEditingController(text: settings.upiId);
        _footerController = TextEditingController(text: settings.receiptFooter);
        _taxPercentController = TextEditingController(text: settings.taxPercent.toString());
        _defaultDiscountController = TextEditingController(text: settings.defaultDiscount.toString());
        _taxEnabled = settings.taxEnabled;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load settings.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _service.update({
        'cafeName': _cafeNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'gstNumber': _gstController.text.trim(),
        'upiId': _upiController.text.trim(),
        'receiptFooter': _footerController.text.trim(),
        'taxEnabled': _taxEnabled,
        'taxPercent': double.tryParse(_taxPercentController.text) ?? 0,
        'defaultDiscount': double.tryParse(_defaultDiscountController.text) ?? 0,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _logoutAllDevices() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout all devices?'),
        content: const Text('This will end all active sessions for your account, including this one.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout All')),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService().logoutAllDevices();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged out from all devices. You may need to log in again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle('Business Profile'),
                    _field(_cafeNameController, 'Cafe Name'),
                    _field(_phoneController, 'Phone'),
                    _field(_addressController, 'Address'),
                    _field(_gstController, 'GST Number (optional)'),
                    _field(_upiController, 'UPI ID'),
                    const SizedBox(height: 20),
                    _sectionTitle('Billing'),
                    _field(_footerController, 'Receipt Footer', maxLines: 2),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Tax'),
                      value: _taxEnabled,
                      onChanged: (v) => setState(() => _taxEnabled = v),
                    ),
                    if (_taxEnabled) _field(_taxPercentController, 'Tax Percent (%)', keyboardType: TextInputType.number),
                    _field(_defaultDiscountController, 'Default Discount (₹)', keyboardType: TextInputType.number),
                    const SizedBox(height: 20),
                    ElevatedButton(onPressed: _save, child: const Text('Save Settings')),
                    const SizedBox(height: 28),
                    _sectionTitle('Security'),
                    Container(
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: ListTile(
                        leading: const Icon(Icons.devices_outlined),
                        title: const Text('Logout All Devices'),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                        onTap: _logoutAllDevices,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _sectionTitle('App'),
                    const _AppInfoTile(),
                  ],
                ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(controller: controller, maxLines: maxLines, keyboardType: keyboardType, decoration: InputDecoration(labelText: label)),
    );
  }
}

class _AppInfoTile extends StatelessWidget {
  const _AppInfoTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data != null ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})' : '—';
        return Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              const ListTile(leading: Icon(Icons.local_cafe_outlined), title: Text('FAST N FRESH CAFE'), subtitle: Text('Cafe Management & POS')),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('Version'), subtitle: Text(version)),
            ],
          ),
        );
      },
    );
  }
}
