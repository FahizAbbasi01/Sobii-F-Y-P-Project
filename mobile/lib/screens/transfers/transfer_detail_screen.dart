import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class TransferDetailScreen extends StatefulWidget {
  const TransferDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  late Future<Transfer> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Transfer> _load() async {
    final data = await context.read<ApiClient>().get('/transfers/${widget.id}') as Map<String, dynamic>;
    return Transfer.fromJson(data['transfer'] as Map<String, dynamic>);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _confirm(Transfer t) async {
    final message = t.isSender
        ? 'Confirm only after you have handed the phone over and received payment. When the buyer also confirms, ownership moves to them permanently.'
        : 'Confirm only after you have the phone, checked that *#06# shows IMEI ending ${t.imeiLast4 ?? '….'}, and are happy with it. When the seller also confirms, you become the registered owner.';
    if (!await confirmDialog(context, title: 'Confirm transfer?', message: message, confirm: 'I confirm')) return;
    await _run(() async {
      final res = await context.read<ApiClient>().post('/transfers/${t.id}/confirm') as Map<String, dynamic>;
      if (!mounted) return;
      if (res['completed'] == true) {
        context.read<AuthState>().refreshMe().catchError((_) {});
        showSnack(context, 'Transfer complete — ownership updated.');
      } else {
        showSnack(context, 'Confirmed. Waiting for the other party.');
      }
    });
  }

  Future<void> _cancel(Transfer t) async {
    if (!await confirmDialog(context, title: 'Cancel transfer?', message: 'The device stays with its current owner and any reserved listing re-opens.', confirm: 'Cancel transfer', danger: true)) return;
    await _run(() => context.read<ApiClient>().post('/transfers/${t.id}/cancel'), success: 'Transfer cancelled');
  }

  Future<void> _dispute(Transfer t) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Raise a dispute', style: AppText.headlineMd),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('This freezes the transfer until an admin reviews it.', style: AppText.bodyMd),
          const SizedBox(height: 12),
          TextField(controller: reason, maxLines: 4, maxLength: 2000, decoration: fieldDecoration(hint: 'What went wrong? (min 10 characters)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit', style: TextStyle(color: AppColors.redText))),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    if (text.length < 10) {
      if (mounted) showSnack(context, 'Please describe the problem (at least 10 characters).', error: true);
      return;
    }
    await _run(() => context.read<ApiClient>().post('/transfers/${t.id}/dispute', {'reason': text}), success: 'Dispute submitted to admins');
  }

  Future<void> _run(Future<dynamic> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) showSnack(context, success);
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Ownership Transfer'),
      body: AsyncView<Transfer>(
        future: _future,
        onRetry: _reload,
        builder: (context, t) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          AppCard(
            accent: switch (t.status) { 'completed' => AppColors.green, 'pending' => AppColors.amber, _ => AppColors.red },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(t.deviceName, style: AppText.headlineLg)), statusBadge(t.status)]),
              const SizedBox(height: 4),
              if (t.imeiLast4 != null) Text('IMEI ending ${t.imeiLast4}', style: AppText.monoData),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _party('From', t.fromName, t.isSender)),
                const Icon(Icons.arrow_forward_rounded, color: AppColors.blue),
                const SizedBox(width: 12),
                Expanded(child: _party('To', t.toName, !t.isSender)),
              ]),
            ]),
          ),
          const SectionHeader('Confirmations'),
          AppCard(
            child: Column(children: [
              _step('Seller / sender confirmed', t.senderConfirmedAt),
              const Divider(height: 20),
              _step('Buyer / recipient confirmed', t.recipientConfirmedAt),
              const Divider(height: 20),
              _step('Ownership updated', t.completedAt),
            ]),
          ),
          const SizedBox(height: 16),
          if (t.status == 'pending') ...[
            if (!t.youConfirmed)
              AppButton(label: 'Confirm transfer', icon: Icons.verified_rounded, kind: ButtonKind.navy, loading: _busy, onPressed: () => _confirm(t))
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Text('You\'ve confirmed. Waiting for ${t.isSender ? t.toName : t.fromName} to confirm.', style: AppText.bodyMd.copyWith(color: AppColors.amberText)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AppButton(label: 'Cancel', kind: ButtonKind.ghost, onPressed: _busy ? null : () => _cancel(t))),
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: 'Dispute', kind: ButtonKind.dangerOutline, onPressed: _busy ? null : () => _dispute(t))),
            ]),
          ],
          if (t.status == 'disputed')
            const PtaDisclaimer(text: 'This transfer is frozen while an admin reviews the dispute. You will be notified of the outcome.'),
          if (t.status == 'completed' && !t.isSender)
            AppButton(label: 'View my device', kind: ButtonKind.ghost, icon: Icons.phone_android_rounded, onPressed: () => context.push('/devices/${t.deviceId}')),
          const SizedBox(height: 16),
          const PtaDisclaimer(
            text: 'DeviceTrust records ownership in its own registry only. It does not handle payments or change PTA/DIRBS records. Meet in a safe public place.',
          ),
        ]),
      ),
    );
  }

  Widget _party(String label, String name, bool you) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: AppText.labelSm),
        const SizedBox(height: 2),
        Text(you ? '$name (you)' : name, style: AppText.labelLg),
      ]);

  Widget _step(String label, String? at) => Row(children: [
        Icon(at != null ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: at != null ? AppColors.greenText : AppColors.muted),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: AppText.labelLg)),
        Text(at != null ? formatDateTime(at) : 'Waiting', style: AppText.bodySm),
      ]);
}
