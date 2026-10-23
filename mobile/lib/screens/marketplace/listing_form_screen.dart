import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Create (deviceId given) or edit (listingId given) a marketplace listing.
class ListingFormScreen extends StatefulWidget {
  const ListingFormScreen({super.key, this.deviceId, this.listingId});
  final String? deviceId;
  final String? listingId;

  @override
  State<ListingFormScreen> createState() => _ListingFormScreenState();
}

class _ListingFormScreenState extends State<ListingFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  String? _condition;
  String? _city;
  final List<XFile> _newPhotos = [];
  List<ListingImage> _existing = [];
  String? _deviceLabel;

  bool get _editing => widget.listingId != null;
  late Future<void> _ready;
  bool _busy = false;
  String _busyLabel = '';

  @override
  void initState() {
    super.initState();
    _ready = _prefill();
  }

  Future<void> _prefill() async {
    final api = context.read<ApiClient>();
    if (_editing) {
      final data = await api.get('/listings/${widget.listingId}') as Map<String, dynamic>;
      final l = Listing.fromJson(data['listing'] as Map<String, dynamic>);
      _title.text = l.title;
      _price.text = l.price.round().toString();
      _description.text = l.description ?? '';
      _condition = l.condition;
      _city = pakistanCities.contains(l.city) ? l.city : null;
      _existing = l.images;
      _deviceLabel = '${l.brand} ${l.model}';
    } else {
      final data = await api.get('/devices/${widget.deviceId}') as Map<String, dynamic>;
      final d = Device.fromJson(data['device'] as Map<String, dynamic>);
      _deviceLabel = d.name;
      _title.text = [d.name, if (d.storageGb != null) '${d.storageGb}GB', if (d.color != null) d.color].join(' ');
      if (d.isStolen) throw ApiException(409, 'device_stolen', 'This device is flagged stolen and cannot be listed.');
      if (d.liveListing != null) throw ApiException(409, 'listed', 'This device already has a live listing.');
    }
  }

  int get _photoCount => _existing.length + _newPhotos.length;

  Future<void> _addPhotos() async {
    final remaining = 6 - _photoCount;
    if (remaining <= 0) {
      showSnack(context, 'Maximum 6 photos', error: true);
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final List<XFile> picked;
    if (source == ImageSource.gallery) {
      picked = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
    } else {
      final shot = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      picked = shot == null ? <XFile>[] : <XFile>[shot];
    }
    if (!mounted) return;
    setState(() => _newPhotos.addAll(picked.take(remaining)));
  }

  Future<void> _deleteExisting(ListingImage img) async {
    try {
      await context.read<ApiClient>().delete('/listings/${widget.listingId}/images/${img.id}');
      setState(() => _existing.remove(img));
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_condition == null) {
      showSnack(context, 'Choose the phone\'s condition', error: true);
      return;
    }
    final api = context.read<ApiClient>();
    final body = {
      'title': _title.text.trim(),
      'price': int.parse(_price.text),
      'condition': _condition,
      'city': _city,
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
    };
    setState(() {
      _busy = true;
      _busyLabel = _editing ? 'Saving…' : 'Publishing…';
    });
    try {
      String id;
      if (_editing) {
        await api.patch('/listings/${widget.listingId}', body);
        id = widget.listingId!;
      } else {
        final data = await api.post('/listings', {...body, 'deviceId': widget.deviceId}) as Map<String, dynamic>;
        id = (data['listing'] as Map)['id'] as String;
      }
      if (_newPhotos.isNotEmpty) {
        setState(() => _busyLabel = 'Uploading ${_newPhotos.length} photo(s)…');
        try {
          await api.multipart('/listings/$id/images', files: _newPhotos.map((p) => UploadFile('images', p.path)).toList());
        } catch (e) {
          if (mounted) showSnack(context, 'Listing saved, but photos failed: $e', error: true);
        }
      }
      if (!mounted) return;
      showSnack(context, _editing ? 'Listing updated' : 'Your phone is live on the marketplace');
      if (_editing) {
        context.pop(true);
      } else {
        context.pushReplacement('/listing/$id');
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, _editing ? 'Edit Listing' : 'Create Listing'),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(error: snap.error!);
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              if (_deviceLabel != null)
                AppCard(
                  child: Row(children: [
                    const Icon(Icons.verified_rounded, color: AppColors.greenText),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$_deviceLabel — registered to you', style: AppText.labelLg)),
                  ]),
                ),
              const SizedBox(height: 16),
              Text('Photos ($_photoCount/6)', style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 92,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final img in _existing) _thumb(NetImage(img.url, iconSize: 24), () => _deleteExisting(img)),
                  for (final p in _newPhotos) _thumb(Image.file(File(p.path), fit: BoxFit.cover), () => setState(() => _newPhotos.remove(p))),
                  if (_photoCount < 6)
                    InkWell(
                      onTap: _addPhotos,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        width: 92,
                        decoration: BoxDecoration(
                          color: AppColors.blueBg,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.blue, width: 1.2),
                        ),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_a_photo_outlined, color: AppColors.blue),
                          SizedBox(height: 4),
                          Text('Add', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              AppField(
                label: 'Title',
                controller: _title,
                maxLength: 120,
                validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
              ),
              AppField(
                label: 'Price (PKR)',
                controller: _price,
                icon: Icons.payments_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a price' : null,
              ),
              Text('Condition', style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in conditionLabels.entries)
                  ChoiceChip(label: Text(e.value), selected: _condition == e.key, onSelected: (_) => setState(() => _condition = e.key)),
              ]),
              const SizedBox(height: 16),
              AppDropdown<String>(
                label: 'City',
                value: _city,
                icon: Icons.location_on_outlined,
                items: pakistanCities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _city = v),
                validator: (v) => v == null ? 'Choose a city' : null,
              ),
              AppField(
                label: 'Description',
                controller: _description,
                hint: 'Battery health, accessories, PTA status, any scratches…',
                maxLines: 5,
                maxLength: 2000,
              ),
              AppButton(
                label: _busy ? _busyLabel : (_editing ? 'Save changes' : 'Publish listing'),
                icon: Icons.check_rounded,
                loading: _busy,
                onPressed: _submit,
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _thumb(Widget image, VoidCallback onRemove) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: SizedBox(width: 92, height: 92, child: image)),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xCC000D23), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ]),
      );
}
