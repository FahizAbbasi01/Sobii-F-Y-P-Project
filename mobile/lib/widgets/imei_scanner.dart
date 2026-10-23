import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/imei.dart';
import '../core/theme.dart';
import 'common.dart';

/// Takes a photo (box label, sticker, or the *#06# screen of another phone),
/// runs on-device ML Kit text recognition, and returns a Luhn-valid IMEI.
/// Returns null if the user cancels or nothing valid is found.
Future<String?> scanImei(BuildContext context, {ImageSource source = ImageSource.camera}) async {
  if (!Platform.isAndroid) {
    showSnack(context, 'Camera scanning works on Android only. Enter the IMEI manually.', error: true);
    return null;
  }
  final XFile? photo;
  try {
    photo = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2000);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not open the camera: $e', error: true);
    return null;
  }
  if (photo == null) return null;

  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  List<String> found;
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
    found = Imei.extractFromText(result.text);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Text recognition failed. Try again or type the IMEI.', error: true);
    return null;
  } finally {
    recognizer.close();
  }

  if (!context.mounted) return null;
  if (found.isEmpty) {
    showSnack(context, 'No valid IMEI found. Hold the label steady in good light, or type it in.', error: true);
    return null;
  }
  if (found.length == 1) return found.first;

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('${found.length} IMEIs found', style: AppText.headlineMd),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Dual-SIM phones have two. Pick the one you want.', style: AppText.bodySm),
        ),
        for (final imei in found)
          ListTile(
            leading: const Icon(Icons.sim_card_outlined, color: AppColors.blue),
            title: Text(formatImei(imei), style: AppText.monoImei),
            onTap: () => Navigator.pop(ctx, imei),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// IMEI text field with quad grouping, live validation, and a scan button.
class ImeiField extends StatelessWidget {
  const ImeiField({super.key, required this.controller, this.label = 'IMEI', this.optional = false, this.onChanged});
  final TextEditingController controller;
  final String label;
  final bool optional;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppField(
      label: label,
      controller: controller,
      hint: '15 digits — dial *#06# to see it',
      icon: Icons.fingerprint_rounded,
      keyboardType: TextInputType.number,
      style: AppText.monoImei,
      maxLength: 15,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
      validator: (v) {
        if (optional && (v ?? '').trim().isEmpty) return null;
        return Imei.validate(v ?? '');
      },
      suffix: IconButton(
        tooltip: 'Scan with camera',
        icon: const Icon(Icons.document_scanner_outlined, color: AppColors.blue),
        onPressed: () async {
          final imei = await scanImei(context);
          if (imei != null) {
            controller.text = imei;
            onChanged?.call(imei);
          }
        },
      ),
    );
  }
}
