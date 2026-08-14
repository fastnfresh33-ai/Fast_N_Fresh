import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/dashboard_models.dart';
import '../../services/misc_services.dart';

class StaffDetailScreen extends StatefulWidget {
  final String staffId;
  const StaffDetailScreen({super.key, required this.staffId});

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  final _service = StaffService();
  StaffPerformance? _performance;
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
      final performance = await _service.getDetail(widget.staffId);
      setState(() => _performance = performance);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load staff details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus() async {
    final staff = _performance!.staff;
    final newStatus = staff.status == 'active' ? 'inactive' : 'active';
    try {
      await _service.update(staff.id, {'status': newStatus});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'New Password')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true || controller.text.length < 6) return;

    try {
      await _service.resetPassword(widget.staffId, controller.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_performance?.staff.name ?? 'Staff')),
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final p = _performance!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primaryLight,
                child: Text(p.staff.name.isNotEmpty ? p.staff.name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 22)),
              ),
              const SizedBox(height: 10),
              Text(p.staff.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const Text('Staff', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(p.staff.phone, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(
                children: [
                  Text(Formatters.currency(p.todaySales), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  const Text("Today's Sales", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(
                children: [
                  Text('${p.todayBills}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 4),
                  const Text('Bills Today', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: _resetPassword, icon: const Icon(Icons.lock_reset, size: 18), label: const Text('Reset Password')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _toggleStatus,
          icon: Icon(p.staff.status == 'active' ? Icons.block : Icons.check_circle_outline, size: 18, color: p.staff.status == 'active' ? AppColors.danger : AppColors.success),
          label: Text(
            p.staff.status == 'active' ? 'Deactivate Staff' : 'Activate Staff',
            style: TextStyle(color: p.staff.status == 'active' ? AppColors.danger : AppColors.success),
          ),
          style: OutlinedButton.styleFrom(side: BorderSide(color: p.staff.status == 'active' ? AppColors.danger : AppColors.success)),
        ),
      ],
    );
  }
}
