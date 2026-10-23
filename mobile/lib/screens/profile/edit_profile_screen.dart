import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String? _city;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthState>().user!;
    _name = TextEditingController(text: u.fullName);
    final p = u.phone ?? '';
    _phone = TextEditingController(text: p.startsWith('+92') ? p.substring(3) : p);
    _city = pakistanCities.contains(u.city) ? u.city : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
      await context.read<ApiClient>().patch('/auth/me', {
        'fullName': _name.text.trim(),
        'phone': digits.isEmpty ? null : '+92${digits.startsWith('0') ? digits.substring(1) : digits}',
        'city': _city,
      });
      if (!mounted) return;
      await context.read<AuthState>().refreshMe();
      if (!mounted) return;
      showSnack(context, 'Profile updated');
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
      appBar: appBar(context, 'Edit Profile'),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AppField(
            label: 'Full name',
            controller: _name,
            icon: Icons.badge_outlined,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
          ),
          AppField(
            label: 'Mobile number',
            controller: _phone,
            prefixText: '+92 ',
            icon: Icons.sim_card_outlined,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            validator: (v) {
              final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
              if (d.isEmpty) return null;
              return (d.length == 10 || (d.length == 11 && d.startsWith('0'))) ? null : 'Enter a valid mobile number';
            },
          ),
          AppDropdown<String>(
            label: 'City',
            value: _city,
            icon: Icons.location_on_outlined,
            items: pakistanCities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _city = v),
          ),
          const SizedBox(height: 8),
          AppButton(label: 'Save', loading: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
