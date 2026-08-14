import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/state_widgets.dart';
import '../../models/user.dart';
import '../../services/misc_services.dart';

/// Admin-only. Lets the admin see every staff/manager (and admin) account
/// and change roles between Staff and Manager. Never allows creating or
/// changing an Admin account here — that stays with the existing
/// authentication/seed flow, and the backend independently refuses it too.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _service = UserService();
  List<AppUser> _users = [];
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
      final users = await _service.list();
      setState(() => _users = users);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load users.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeRole(AppUser user) async {
    final newRole = user.role == 'staff' ? 'manager' : 'staff';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Role'),
        content: Text('Change ${user.name} from ${user.role} to $newRole?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.changeRole(user.id, newRole);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleStatus(AppUser user) async {
    final newStatus = user.status == 'active' ? 'inactive' : 'active';
    try {
      await _service.changeStatus(user.id, newStatus);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addUser() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddUserSheet(),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users & Roles')),
      floatingActionButton: FloatingActionButton(onPressed: _addUser, child: const Icon(Icons.person_add_alt)),
      body: _loading
          ? const LoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _users.isEmpty
                  ? const EmptyState(icon: Icons.people_outline, title: 'No users yet')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _UserTile(
                          user: _users[i],
                          onChangeRole: () => _changeRole(_users[i]),
                          onToggleStatus: () => _toggleStatus(_users[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onChangeRole;
  final VoidCallback onToggleStatus;
  const _UserTile({required this.user, required this.onChangeRole, required this.onToggleStatus});

  Color get _roleColor {
    if (user.isAdmin) return AppColors.primary;
    if (user.isManager) return AppColors.info;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: _roleColor.withValues(alpha: 0.12),
              child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: TextStyle(color: _roleColor, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(user.phone, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _roleColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(user.role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _roleColor)),
              ),
              const SizedBox(height: 4),
              Text(user.status == 'active' ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, color: user.status == 'active' ? AppColors.success : AppColors.textMuted)),
            ]),
          ]),
          if (!user.isAdmin) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onChangeRole,
                  child: Text('Change Role → ${user.role == 'staff' ? 'Manager' : 'Staff'}'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onToggleStatus,
                style: OutlinedButton.styleFrom(side: BorderSide(color: user.status == 'active' ? AppColors.danger : AppColors.success)),
                child: Text(
                  user.status == 'active' ? 'Deactivate' : 'Activate',
                  style: TextStyle(color: user.status == 'active' ? AppColors.danger : AppColors.success),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _AddUserSheet extends StatefulWidget {
  const _AddUserSheet();

  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'staff';
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserService().create(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        role: _role,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 16),
              Text('Add Staff or Manager', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ChoiceChip(label: const Text('Staff'), selected: _role == 'staff', onSelected: (_) => setState(() => _role = 'staff'))),
                const SizedBox(width: 10),
                Expanded(child: ChoiceChip(label: const Text('Manager'), selected: _role == 'manager', onSelected: (_) => setState(() => _role = 'manager'))),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
