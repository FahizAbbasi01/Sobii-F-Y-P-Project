import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/imei.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/imei_scanner.dart';

class ImeiCheckScreen extends StatefulWidget {
  const ImeiCheckScreen({super.key, this.initialImei});
  final String? initialImei;

  @override
  State<ImeiCheckScreen> createState() => _ImeiCheckScreenState();
}

class _ImeiCheckScreenState extends State<ImeiCheckScreen> {
  final _form = GlobalKey<FormState>();
  final _imei = TextEditingController();
  RegistryResult? _result;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialImei != null) {
      _imei.text = widget.initialImei!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final data = await context.read<ApiClient>().get('/registry/${Imei.normalize(_imei.text)}');
      if (mounted) setState(() => _result = RegistryResult.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _imei.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'IMEI Verification', back: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Text('Check before you buy', style: AppText.headlineLg),
        const SizedBox(height: 4),
        Text('Dial *#06# on the phone you\'re buying, then type or scan the number it shows.', style: AppText.bodyMd),
        const SizedBox(height: 20),
        Form(key: _form, child: ImeiField(controller: _imei, label: '15-digit IMEI')),
        AppButton(label: 'Verify IMEI', icon: Icons.manage_search_rounded, onPressed: _check, loading: _busy, kind: ButtonKind.navy),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            final imei = await scanImei(context);
            if (imei != null) {
              _imei.text = imei;
              _check();
            }
          },
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Scan IMEI from box or screen'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorView(error: _error!, onRetry: _check),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          _ResultCard(result: _result!),
        ],
        const SizedBox(height: 20),
        const PtaDisclaimer(),
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final RegistryResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final d = r.device;
    final (Color accent, IconData icon, String title, String message) = switch (r.status) {
      'registered' => (
          AppColors.green,
          Icons.verified_rounded,
          'Registered',
          (d?['ownedByYou'] == true)
              ? 'This device is registered to you.'
              : 'This IMEI is registered to a DeviceTrust user and has no approved theft report.',
        ),
      'reported_stolen' => (
          AppColors.red,
          Icons.gpp_bad_rounded,
          'Reported Stolen',
          'The registered owner reported this device stolen and it was approved. Do not buy it — consider informing the police.',
        ),
      'not_found' => (
          AppColors.amber,
          Icons.help_outline_rounded,
          'Not Found',
          'This IMEI isn\'t in the DeviceTrust registry. That does NOT mean it\'s clean or stolen — only that nobody has registered it here.',
        ),
      _ => (AppColors.red, Icons.error_outline_rounded, 'Invalid IMEI', r.reason ?? 'This is not a valid IMEI.'),
    };
    return AppCard(
      accent: accent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppText.headlineLg)),
          statusBadge(r.status),
        ]),
        const SizedBox(height: 10),
        Text(message, style: AppText.bodyMd),
        const SizedBox(height: 12),
        ImeiText(r.imei, label: 'IMEI'),
        if (d != null) ...[
          const Divider(height: 24),
          _row('Device', '${d['brand']} ${d['model']}${d['storageGb'] != null ? ' • ${d['storageGb']}GB' : ''}'),
          _row('Registered since', formatDate(d['registeredSince'] as String?)),
          _row('Recorded owners', '${d['ownerCount']}'),
          if (d['reportUnderReview'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: StatusBadge('Theft report under review', kind: BadgeKind.warning, icon: Icons.schedule),
            ),
          if (d['activeListingId'] != null && r.status == 'registered') ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'View marketplace listing',
              kind: ButtonKind.ghost,
              icon: Icons.storefront_outlined,
              onPressed: () => context.push('/listing/${d['activeListingId']}'),
            ),
          ],
        ],
        const SizedBox(height: 8),
        Text('Checked ${formatDateTime(r.checkedAt)} • Source: DeviceTrust registry', style: AppText.monoData),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 130, child: Text(k, style: AppText.bodySm)),
          Expanded(child: Text(v, style: AppText.labelLg)),
        ]),
      );
}
