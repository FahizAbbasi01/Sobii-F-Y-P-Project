import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../demo/demo_backend.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 30),
      ),
      const SizedBox(height: 20),
      Text(title, style: AppText.headlineXl),
      const SizedBox(height: 6),
      Text(subtitle, style: AppText.bodyMd),
      const SizedBox(height: 28),
    ]);
  }
}

String? emailValidator(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email';
  return null;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = context.read<AuthState>().startupError;
  }

  Future<void> _useDemoAccount() async {
    _email.text = DemoBackend.demoEmail;
    _password.text = DemoBackend.demoPassword;
    await _submit();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(_email.text.trim(), _password.text);
      // Router redirects to /home on success.
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AuthHeader(title: 'Welcome Back', subtitle: 'Log in to verify devices, manage listings, and buy safely.'),
              if (Provider.of<ApiClient>(context, listen: false).isDemo) ...[
                AppCard(
                  accent: AppColors.amber,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Demo account', style: AppText.labelLg),
                      const SizedBox(width: 8),
                      const DemoBadge(),
                    ]),
                    const SizedBox(height: 6),
                    Text('Email: ${DemoBackend.demoEmail}\nPassword: ${DemoBackend.demoPassword}', style: AppText.monoData),
                    const SizedBox(height: 10),
                    AppButton(
                      key: const Key('demo-login'),
                      label: 'Use demo account',
                      icon: Icons.play_circle_outline_rounded,
                      kind: ButtonKind.primary,
                      loading: _busy,
                      onPressed: _useDemoAccount,
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
              ],
              AppField(
                label: 'Email',
                controller: _email,
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: emailValidator,
              ),
              AppField(
                label: 'Password',
                controller: _password,
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                textInputAction: TextInputAction.done,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.slate),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.redBg, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Text(_error!, style: AppText.bodyMd.copyWith(color: AppColors.redText)),
                ),
                const SizedBox(height: 16),
              ],
              AppButton(label: 'Log In', icon: Icons.login_rounded, onPressed: _submit, loading: _busy, kind: ButtonKind.navy),
              const SizedBox(height: 24),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text("Don't have an account? ", style: AppText.bodyMd),
                  GestureDetector(
                    onTap: () => context.go('/register'),
                    child: Text('Create an Account', style: AppText.labelLg.copyWith(color: AppColors.blue)),
                  ),
                ]),
              ),
              const SizedBox(height: 32),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_rounded, size: 14, color: AppColors.muted),
                SizedBox(width: 6),
                Flexible(child: Text('Secure sign-in', style: TextStyle(fontSize: 12, color: AppColors.muted))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
