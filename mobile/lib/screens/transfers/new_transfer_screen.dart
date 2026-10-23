import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/login_screen.dart' show emailValidator;

/// Direct transfer (gift / sale arranged outside the marketplace) to another DeviceTrust user.
class NewTransferScreen extends StatefulWidget {
  const NewTransferScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  State<NewTransferScreen> createState() => _NewTransferScreenState();
}

class _NewTransferScreenState extends State<NewTransferScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!await confirmDialog(
      context,
      title: 'Start transfer?',
      message: '${_email.text.trim()} will be asked to accept. Ownership moves only after you BOTH confirm.',
      confirm: 'Start',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await context.read<ApiClient>().post('/transfers', {'deviceId': widget.deviceId, 'recipientEmail': _email.text.trim()}) as Map<String, dynamic>;
      if (!mounted) return;
      showSnack(context, 'Transfer started');
      context.pushReplacement('/transfers/${(res['transfer'] as Map)['id']}');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Transfer Ownership'),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Text('Send to another DeviceTrust user', style: AppText.headlineLg),
          const SizedBox(height: 6),
          Text('Use this when you\'ve sold or gifted the phone outside the marketplace. The recipient must already have an account.', style: AppText.bodyMd),
          const SizedBox(height: 20),
          AppField(
            label: 'Recipient\'s email',
            controller: _email,
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: emailValidator,
          ),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How it works', style: AppText.labelLg),
              const SizedBox(height: 8),
              Text('1. You start the transfer.\n2. You and the recipient each tap Confirm.\n3. Only then does the registry show them as owner.', style: AppText.bodyMd),
            ]),
          ),
          const SizedBox(height: 20),
          AppButton(label: 'Start transfer', icon: Icons.swap_horiz_rounded, kind: ButtonKind.navy, loading: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
