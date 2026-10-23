import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/listing_card.dart';

class BrowseFilters {
  String? brand;
  String? condition;
  String? city;
  int? minPrice;
  int? maxPrice;
  int? minStorage;
  String sort = 'newest';

  BrowseFilters copy() => BrowseFilters()
    ..brand = brand
    ..condition = condition
    ..city = city
    ..minPrice = minPrice
    ..maxPrice = maxPrice
    ..minStorage = minStorage
    ..sort = sort;

  int get activeCount => [brand, condition, city, minPrice, maxPrice, minStorage].where((v) => v != null).length;
}

const _sortLabels = {
  'newest': 'Newest first',
  'price_asc': 'Price: low to high',
  'price_desc': 'Price: high to low',
  'oldest': 'Oldest first',
};

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, this.initialQuery, this.initialBrand});
  final String? initialQuery;
  final String? initialBrand;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  BrowseFilters _filters = BrowseFilters();
  final List<Listing> _items = [];
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialQuery ?? '';
    _filters.brand = (widget.initialBrand?.isEmpty ?? true) ? null : widget.initialBrand;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400 && !_loading && _items.length < _total) _fetch();
    });
    _reload();
  }

  @override
  void didUpdateWidget(BrowseScreen old) {
    super.didUpdateWidget(old);
    // Arriving from Home with a new search/brand.
    if (old.initialQuery != widget.initialQuery || old.initialBrand != widget.initialBrand) {
      _search.text = widget.initialQuery ?? '';
      _filters.brand = (widget.initialBrand?.isEmpty ?? true) ? null : widget.initialBrand;
      _reload();
    }
  }

  void _reload() {
    _page = 1;
    _items.clear();
    _total = 0;
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = _filters;
      final data = await context.read<ApiClient>().get('/listings', query: {
        'q': _search.text.trim(),
        'brand': f.brand,
        'condition': f.condition,
        'city': f.city,
        'minPrice': f.minPrice,
        'maxPrice': f.maxPrice,
        'minStorage': f.minStorage,
        'sort': f.sort,
        'page': _page,
        'limit': 20,
      }) as Map<String, dynamic>;
      final list = (data['listings'] as List).map((e) => Listing.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _total = (data['total'] as num).toInt();
        _page += 1;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _reload);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<BrowseFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => _FilterSheet(initial: _filters.copy()),
    );
    if (result != null) {
      setState(() => _filters = result);
      _reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Explore Marketplace', back: false),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: fieldDecoration(hint: 'Search brand, model…', icon: Icons.search_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _filters.activeCount > 0,
              label: Text('${_filters.activeCount}'),
              child: Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.white), onPressed: _openFilters, tooltip: 'Filters'),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip(Icons.sort_rounded, _sortLabels[_filters.sort]!, true, _pickSort),
              if (_filters.brand != null) _chip(Icons.close, _filters.brand!, true, () => _clear(() => _filters.brand = null)),
              if (_filters.condition != null) _chip(Icons.close, conditionLabel(_filters.condition), true, () => _clear(() => _filters.condition = null)),
              if (_filters.city != null) _chip(Icons.close, _filters.city!, true, () => _clear(() => _filters.city = null)),
              if (_filters.minPrice != null || _filters.maxPrice != null)
                _chip(Icons.close, '${_filters.minPrice ?? 0} – ${_filters.maxPrice ?? '∞'}', true, () => _clear(() {
                      _filters.minPrice = null;
                      _filters.maxPrice = null;
                    })),
              if (_filters.minStorage != null) _chip(Icons.close, '${_filters.minStorage}GB+', true, () => _clear(() => _filters.minStorage = null)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Text(_loading && _items.isEmpty ? 'Searching…' : '$_total phone${_total == 1 ? '' : 's'} found', style: AppText.labelMd),
          ]),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  void _clear(VoidCallback fn) {
    setState(fn);
    _reload();
  }

  Future<void> _pickSort() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Text('Sort by', style: AppText.headlineMd),
          for (final e in _sortLabels.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == _filters.sort ? const Icon(Icons.check_rounded, color: AppColors.blue) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (v != null && v != _filters.sort) {
      setState(() => _filters.sort = v);
      _reload();
    }
  }

  Widget _chip(IconData icon, String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: AppColors.blue),
        label: Text(label),
        labelStyle: AppText.labelMd.copyWith(color: AppColors.navy),
        backgroundColor: selected ? AppColors.blueBg : AppColors.surface,
        side: const BorderSide(color: AppColors.outline),
        shape: const StadiumBorder(),
        onPressed: onTap,
      ),
    );
  }

  Widget _body() {
    if (_error != null && _items.isEmpty) return ErrorView(error: _error!, onRetry: _reload);
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: 'No phones match',
        message: 'Try a different search or clear some filters.',
        action: _filters.activeCount > 0 ? 'Clear filters' : null,
        onAction: () => _clear(() => _filters = BrowseFilters()..sort = _filters.sort),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length + (_items.length < _total ? 1 : 0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62),
        itemBuilder: (_, i) {
          if (i >= _items.length) return const LoadingView();
          final l = _items[i];
          return ListingCard(listing: l, onTap: () => context.push('/listing/${l.id}'));
        },
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final BrowseFilters initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late BrowseFilters f = widget.initial;
  late final _brand = TextEditingController(text: f.brand ?? '');
  late final _min = TextEditingController(text: f.minPrice?.toString() ?? '');
  late final _max = TextEditingController(text: f.maxPrice?.toString() ?? '');

  @override
  void dispose() {
    _brand.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('Filters', style: AppText.headlineLg)),
              TextButton(
                onPressed: () => Navigator.pop(context, BrowseFilters()..sort = f.sort),
                child: const Text('Reset'),
              ),
            ]),
            const SizedBox(height: 12),
            AppField(label: 'Brand', controller: _brand, hint: 'e.g. Samsung', icon: Icons.smartphone_rounded),
            Text('Condition', style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in conditionLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: f.condition == e.key,
                  onSelected: (s) => setState(() => f.condition = s ? e.key : null),
                ),
            ]),
            const SizedBox(height: 16),
            AppDropdown<String?>(
              label: 'City',
              value: f.city,
              icon: Icons.location_on_outlined,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Any city')),
                ...pakistanCities.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
              ],
              onChanged: (v) => setState(() => f.city = v),
            ),
            Row(children: [
              Expanded(child: AppField(label: 'Min price (PKR)', controller: _min, keyboardType: TextInputType.number, inputFormatters: digits)),
              const SizedBox(width: 12),
              Expanded(child: AppField(label: 'Max price (PKR)', controller: _max, keyboardType: TextInputType.number, inputFormatters: digits)),
            ]),
            Text('Minimum storage', style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final gb in [64, 128, 256, 512])
                ChoiceChip(label: Text('${gb}GB+'), selected: f.minStorage == gb, onSelected: (s) => setState(() => f.minStorage = s ? gb : null)),
            ]),
            const SizedBox(height: 24),
            AppButton(
              label: 'Show results',
              onPressed: () {
                f.brand = _brand.text.trim().isEmpty ? null : _brand.text.trim();
                f.minPrice = int.tryParse(_min.text);
                f.maxPrice = int.tryParse(_max.text);
                if (f.minPrice != null && f.maxPrice != null && f.minPrice! > f.maxPrice!) {
                  showSnack(context, 'Min price cannot be higher than max price', error: true);
                  return;
                }
                Navigator.pop(context, f);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
