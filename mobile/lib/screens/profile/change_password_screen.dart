import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../widgets/common.dart';
import '../auth/register_screen.dart' show passwordValidator;

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = context.read<ApiClient>();
      final res = await api.post('/auth/change-password', {'currentPassword': _current.text, 'newPassword': _next.text}) as Map<String, dynamic>;
      await api.tokens.save(res['accessToken'] as String, res['refreshToken'] as String);
      if (!mounted) return;
      showSnack(context, 'Password changed. Other devices have been signed out.');
      context.pop();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Change Password'),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AppField(label: 'Current password', controller: _current, obscure: true, icon: Icons.lock_outline_rounded, validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
          AppField(label: 'New password', controller: _next, obscure: true, icon: Icons.lock_reset_rounded, validator: passwordValidator),
          AppField(
            label: 'Repeat new password',
            controller: _again,
            obscure: true,
            icon: Icons.lock_reset_rounded,
            validator: (v) => v != _next.text ? 'Passwords do not match' : null,
          ),
          AppButton(label: 'Change password', loading: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
