import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';

String? passwordValidator(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'At least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) return 'Use letters and numbers';
  return null;
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _city;
  bool _agree = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agree) {
      setState(() => _error = 'Please accept the registry terms to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
      await context.read<AuthState>().register(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _name.text.trim(),
            phone: digits.isEmpty ? null : '+92${digits.startsWith('0') ? digits.substring(1) : digits}',
            city: _city,
          );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, '', actions: const []),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AuthHeader(title: 'Create Account', subtitle: 'Register to list phones, record ownership and buy safely.'),
              AppField(
                label: 'Full legal name',
                controller: _name,
                icon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
              ),
              AppField(
                label: 'Email',
                controller: _email,
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: emailValidator,
              ),
              AppField(
                label: 'Mobile phone number (optional)',
                controller: _phone,
                icon: Icons.sim_card_outlined,
                prefixText: '+92 ',
                hint: '3001234567',
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                validator: (v) {
                  final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (d.isEmpty) return null;
                  return (d.length == 10 || (d.length == 11 && d.startsWith('0'))) ? null : 'Enter a valid Pakistani mobile number';
                },
              ),
              AppDropdown<String>(
                label: 'Primary marketplace hub',
                value: _city,
                icon: Icons.location_on_outlined,
                items: pakistanCities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _city = v),
              ),
              AppField(
                label: 'Password',
                controller: _password,
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                validator: passwordValidator,
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.slate),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _agree = !_agree),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(value: _agree, onChanged: (v) => setState(() => _agree = v ?? false)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'I confirm the information is accurate and agree that my registry actions are recorded in audit logs.',
                        style: AppText.bodySm,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Text(_error!, style: AppText.bodyMd.copyWith(color: AppColors.redText)),
                ),
                const SizedBox(height: 16),
              ],
              AppButton(label: 'Create Account', icon: Icons.person_add_alt_1_rounded, onPressed: _submit, loading: _busy),
              const SizedBox(height: 20),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Already registered? ', style: AppText.bodyMd),
                  GestureDetector(onTap: () => context.go('/login'), child: Text('Log In', style: AppText.labelLg.copyWith(color: AppColors.blue))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
