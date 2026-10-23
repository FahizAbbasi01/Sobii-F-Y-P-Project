import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class StolenReportScreen extends StatefulWidget {
  const StolenReportScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  State<StolenReportScreen> createState() => _StolenReportScreenState();
}

class _StolenReportScreenState extends State<StolenReportScreen> {
  final _form = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _fir = TextEditingController();
  DateTime? _date;
  XFile? _evidence;
  bool _busy = false;
  late Future<Device> _device;

  @override
  void initState() {
    super.initState();
    _device = context.read<ApiClient>().get('/devices/${widget.deviceId}').then((d) => Device.fromJson((d as Map)['device'] as Map<String, dynamic>));
  }

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    _fir.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date ?? now, firstDate: DateTime(now.year - 3), lastDate: now);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickEvidence() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
    if (x != null) setState(() => _evidence = x);
  }

  Future<void> _submit(Device device) async {
    if (!_form.currentState!.validate()) return;
    if (_date == null) {
      showSnack(context, 'Choose the date of the incident', error: true);
      return;
    }
    if (!await confirmDialog(
      context,
      title: 'Report ${device.name} stolen?',
      message: 'Any listing is withdrawn and pending transfers are cancelled now. After an admin approves, anyone checking this IMEI will see "Reported Stolen".',
      confirm: 'Submit report',
      danger: true,
    )) {
      return;
    }
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      final res = await api.post('/stolen-reports', {
        'deviceId': widget.deviceId,
        'incidentDate': DateFormat('yyyy-MM-dd').format(_date!),
        'location': _location.text.trim(),
        'description': _description.text.trim(),
        if (_fir.text.trim().isNotEmpty) 'policeReportNumber': _fir.text.trim(),
      }) as Map<String, dynamic>;
      final reportId = (res['report'] as Map)['id'] as String;
      if (_evidence != null) {
        try {
          await api.multipart('/documents', files: [UploadFile('file', _evidence!.path)], fields: {'kind': 'police_report', 'stolenReportId': reportId, 'deviceId': widget.deviceId});
        } catch (e) {
          if (mounted) showSnack(context, 'Report filed, but the attachment failed: $e', error: true);
        }
      }
      if (!mounted) return;
      showSnack(context, 'Report submitted for admin review');
      context.pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Report Stolen Device'),
      body: AsyncView<Device>(
        future: _device,
        builder: (context, device) => Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            AppCard(
              accent: AppColors.red,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(device.name, style: AppText.headlineMd),
                if (device.primaryImei != null) ImeiText(device.primaryImei!, label: 'IMEI 1', copyable: false),
              ]),
            ),
            const SizedBox(height: 12),
            const PtaDisclaimer(
              text: 'This flags the phone in the DeviceTrust registry only. Also file an FIR with police and request blocking via PTA/DIRBS — DeviceTrust does not do this for you.',
            ),
            const SizedBox(height: 20),
            Text('Date of incident', style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InputDecorator(
                decoration: fieldDecoration(icon: Icons.event_outlined),
                child: Text(_date == null ? 'Select date' : DateFormat('d MMMM yyyy').format(_date!), style: AppText.bodyLg),
              ),
            ),
            const SizedBox(height: 16),
            AppField(
              label: 'Where did it happen?',
              controller: _location,
              hint: 'e.g. Saddar, Rawalpindi',
              icon: Icons.place_outlined,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the location' : null,
            ),
            AppField(
              label: 'What happened?',
              controller: _description,
              maxLines: 4,
              maxLength: 2000,
              validator: (v) => (v == null || v.trim().length < 10) ? 'At least 10 characters' : null,
            ),
            AppField(label: 'FIR / police report number (optional)', controller: _fir, icon: Icons.local_police_outlined),
            Text('Evidence (optional)', style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_evidence != null)
              Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_evidence!.path), width: 64, height: 64, fit: BoxFit.cover)),
                const SizedBox(width: 12),
                Expanded(child: Text('Photo of FIR / receipt attached', style: AppText.bodyMd)),
                IconButton(onPressed: () => setState(() => _evidence = null), icon: const Icon(Icons.close)),
              ])
            else
              AppButton(label: 'Attach FIR or receipt photo', kind: ButtonKind.ghost, icon: Icons.attach_file_rounded, onPressed: _pickEvidence),
            const SizedBox(height: 24),
            AppButton(label: 'Submit stolen report', kind: ButtonKind.danger, icon: Icons.gpp_maybe_rounded, loading: _busy, onPressed: () => _submit(device)),
          ]),
        ),
      ),
    );
  }
}
