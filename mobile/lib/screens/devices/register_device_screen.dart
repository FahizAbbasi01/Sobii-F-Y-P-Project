import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/imei.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/imei_scanner.dart';

const _brands = ['Apple', 'Samsung', 'Xiaomi', 'OPPO', 'Vivo', 'Infinix', 'Tecno', 'Realme', 'OnePlus', 'Google', 'Huawei', 'Nokia', 'Motorola', 'Other'];

class RegisterDeviceScreen extends StatefulWidget {
  const RegisterDeviceScreen({super.key, this.thenSell = false});

  /// When true, goes straight to the listing form after registering.
  final bool thenSell;

  @override
  State<RegisterDeviceScreen> createState() => _RegisterDeviceScreenState();
}

class _RegisterDeviceScreenState extends State<RegisterDeviceScreen> {
  final _form = GlobalKey<FormState>();
  final _imei1 = TextEditingController();
  final _imei2 = TextEditingController();
  final _model = TextEditingController();
  final _otherBrand = TextEditingController();
  final _storage = TextEditingController();
  final _color = TextEditingController();
  String? _brand;
  bool _dualSim = false;
  bool _busy = false;
  bool _confirmOwner = false;

  @override
  void dispose() {
    for (final c in [_imei1, _imei2, _model, _otherBrand, _storage, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_confirmOwner) {
      showSnack(context, 'Please confirm you are the rightful owner of this phone.', error: true);
      return;
    }
    if (_dualSim && Imei.normalize(_imei1.text) == Imei.normalize(_imei2.text)) {
      showSnack(context, 'IMEI 1 and IMEI 2 must be different.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await context.read<ApiClient>().post('/devices', {
        'imei1': Imei.normalize(_imei1.text),
        if (_dualSim) 'imei2': Imei.normalize(_imei2.text),
        'brand': _brand == 'Other' ? _otherBrand.text.trim() : _brand,
        'model': _model.text.trim(),
        if (_storage.text.isNotEmpty) 'storageGb': int.parse(_storage.text),
        if (_color.text.trim().isNotEmpty) 'color': _color.text.trim(),
      }) as Map<String, dynamic>;
      final device = Device.fromJson(data['device'] as Map<String, dynamic>);
      if (!mounted) return;
      context.read<AuthState>().refreshMe().catchError((_) {});
      showSnack(context, '${device.name} registered to you');
      if (widget.thenSell) {
        context.pushReplacement('/listings/new?deviceId=${device.id}');
      } else {
        context.pop(device);
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Register Device'),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          AppCard(
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Dial *#06# on this phone to see its IMEI(s), or tap the scan icon to read them from the box label.',
                  style: AppText.bodySm,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          ImeiField(controller: _imei1, label: 'IMEI 1'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Dual SIM (has a second IMEI)', style: AppText.labelLg),
            value: _dualSim,
            onChanged: (v) => setState(() => _dualSim = v),
          ),
          if (_dualSim) ImeiField(controller: _imei2, label: 'IMEI 2'),
          AppDropdown<String>(
            label: 'Brand',
            value: _brand,
            icon: Icons.business_rounded,
            items: _brands.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (v) => setState(() => _brand = v),
            validator: (v) => v == null ? 'Choose a brand' : null,
          ),
          if (_brand == 'Other')
            AppField(
              label: 'Brand name',
              controller: _otherBrand,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the brand' : null,
            ),
          AppField(
            label: 'Model',
            controller: _model,
            hint: 'e.g. Galaxy S23 Ultra',
            icon: Icons.smartphone_rounded,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the model' : null,
          ),
          Row(children: [
            Expanded(
              child: AppField(
                label: 'Storage (GB)',
                controller: _storage,
                hint: '128',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: AppField(label: 'Colour', controller: _color, hint: 'Black')),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmOwner,
            onChanged: (v) => setState(() => _confirmOwner = v ?? false),
            title: Text('I am the rightful owner of this phone. False registrations are logged and may be reported.', style: AppText.bodySm),
          ),
          const SizedBox(height: 12),
          AppButton(label: widget.thenSell ? 'Register & continue to listing' : 'Register device', kind: ButtonKind.navy, icon: Icons.app_registration_rounded, loading: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
