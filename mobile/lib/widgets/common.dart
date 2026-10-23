import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';

// ---------------- Surfaces ----------------

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.accent, this.margin});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  /// Optional 4px top accent bar (IMEI verification cards).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final body = accent == null
        ? content
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Container(height: 4, color: accent), content]);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      // Only tappable cards get an InkWell; otherwise buttons inside the card stay
      // separately reachable (and accessible to TalkBack / screen readers).
      child: Material(
        color: Colors.transparent,
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

PreferredSizeWidget appBar(BuildContext context, String title, {List<Widget>? actions, bool back = true}) {
  return AppBar(
    title: Text(title, style: AppText.headlineMd),
    backgroundColor: AppColors.canvas,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: back,
    foregroundColor: AppColors.ink,
    actions: actions,
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(children: [
        Expanded(child: Text(title, style: AppText.headlineMd)),
        if (action != null)
          GestureDetector(onTap: onAction, child: Text(action!, style: AppText.labelLg.copyWith(color: AppColors.blue))),
      ]),
    );
  }
}

// ---------------- Buttons ----------------

enum ButtonKind { primary, navy, ghost, danger, dangerOutline }

class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, required this.onPressed, this.kind = ButtonKind.primary, this.icon, this.loading = false, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (kind) {
      ButtonKind.primary => (AppColors.blue, Colors.white, null),
      ButtonKind.navy => (AppColors.navy, Colors.white, null),
      ButtonKind.ghost => (AppColors.surface, AppColors.navy, AppColors.outline),
      ButtonKind.danger => (AppColors.red, Colors.white, null),
      ButtonKind.dangerOutline => (AppColors.surface, AppColors.redText, AppColors.red),
    };
    final disabled = onPressed == null || loading;
    final child = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: AppText.labelLg.copyWith(color: fg), overflow: TextOverflow.ellipsis)),
          ]);
    final button = Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: disabled ? null : onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: border == null
                ? null
                : BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: border, width: 1)),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// ---------------- Inputs ----------------

InputDecoration fieldDecoration({String? hint, IconData? icon, Widget? suffix, String? prefixText}) {
  OutlineInputBorder border(Color c, [double w = 1.5]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    hintStyle: AppText.bodyMd.copyWith(color: AppColors.muted),
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: AppColors.slate),
    prefixText: prefixText,
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border(AppColors.outline),
    enabledBorder: border(AppColors.outline),
    focusedBorder: border(AppColors.blue, 2),
    errorBorder: border(AppColors.red),
    focusedErrorBorder: border(AppColors.red, 2),
  );
}

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.textInputAction,
    this.style,
    this.prefixText,
    this.onChanged,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscure,
          maxLines: maxLines,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          onChanged: onChanged,
          enabled: enabled,
          style: style ?? AppText.bodyLg,
          decoration: fieldDecoration(hint: hint, icon: icon, suffix: suffix, prefixText: prefixText),
        ),
      ]),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.icon, this.validator});
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppText.labelMd.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          // ignore: deprecated_member_use
          value: value,
          items: items,
          onChanged: onChanged,
          validator: validator,
          isExpanded: true,
          decoration: fieldDecoration(icon: icon),
          style: AppText.bodyLg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ]),
    );
  }
}

// ---------------- Badges ----------------

enum BadgeKind { success, warning, danger, info, neutral }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.kind = BadgeKind.neutral, this.icon});
  final String label;
  final BadgeKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (kind) {
      BadgeKind.success => (AppColors.greenBg, AppColors.greenText),
      BadgeKind.warning => (AppColors.amberBg, AppColors.amberText),
      BadgeKind.danger => (AppColors.redBg, AppColors.redText),
      BadgeKind.info => (AppColors.blueBg, AppColors.blueDark),
      BadgeKind.neutral => (AppColors.surfaceLow, AppColors.slate),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: AppText.labelMd.copyWith(color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Maps backend statuses to the right badge colour/icon in one place.
StatusBadge statusBadge(String status) {
  switch (status) {
    case 'registered':
      return const StatusBadge('Registered', kind: BadgeKind.success, icon: Icons.verified);
    case 'reported_stolen':
      return const StatusBadge('Reported stolen', kind: BadgeKind.danger, icon: Icons.gpp_bad);
    case 'not_found':
      return const StatusBadge('Not in registry', kind: BadgeKind.neutral, icon: Icons.help_outline);
    case 'invalid':
      return const StatusBadge('Invalid IMEI', kind: BadgeKind.danger, icon: Icons.error_outline);
    case 'active':
      return const StatusBadge('Active', kind: BadgeKind.success);
    case 'reserved':
      return const StatusBadge('Reserved', kind: BadgeKind.warning, icon: Icons.schedule);
    case 'sold':
      return const StatusBadge('Sold', kind: BadgeKind.info);
    case 'withdrawn':
      return const StatusBadge('Withdrawn', kind: BadgeKind.neutral);
    case 'removed':
      return const StatusBadge('Removed', kind: BadgeKind.danger);
    case 'pending':
      return const StatusBadge('Pending', kind: BadgeKind.warning, icon: Icons.schedule);
    case 'accepted':
      return const StatusBadge('Accepted', kind: BadgeKind.info, icon: Icons.handshake_outlined);
    case 'rejected':
      return const StatusBadge('Rejected', kind: BadgeKind.danger);
    case 'cancelled':
      return const StatusBadge('Cancelled', kind: BadgeKind.neutral);
    case 'completed':
      return const StatusBadge('Completed', kind: BadgeKind.success, icon: Icons.check_circle);
    case 'approved':
      return const StatusBadge('Approved', kind: BadgeKind.success, icon: Icons.check_circle);
    case 'disputed':
      return const StatusBadge('Disputed', kind: BadgeKind.danger, icon: Icons.report_outlined);
    default:
      return StatusBadge(status);
  }
}

// ---------------- IMEI & disclaimers ----------------

class ImeiText extends StatelessWidget {
  const ImeiText(this.imei, {super.key, this.label, this.copyable = true});
  final String imei;
  final String? label;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (label != null) SizedBox(width: 64, child: Text(label!, style: AppText.labelSm)),
      Expanded(child: Text(formatImei(imei), style: AppText.monoImei)),
      if (copyable)
        IconButton(
          tooltip: 'Copy IMEI',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.slate),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: imei));
            showSnack(context, 'IMEI copied');
          },
        ),
    ]);
  }
}

/// Required on every registry result: our registry is NOT the PTA's.
class PtaDisclaimer extends StatelessWidget {
  const PtaDisclaimer({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.slateBg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.slate),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text ??
                'DeviceTrust results come from our own community registry. They are not an official PTA/DIRBS check. '
                    'For official PTA status, SMS the IMEI to 8484.',
            style: AppText.bodySm,
          ),
        ),
      ]),
    );
  }
}

// ---------------- States ----------------

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final net = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(net ? Icons.cloud_off_rounded : Icons.error_outline_rounded, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(net ? 'You\'re offline' : 'Something went wrong', style: AppText.headlineMd),
          const SizedBox(height: 6),
          Text(error.toString(), style: AppText.bodyMd, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            AppButton(label: 'Try again', onPressed: onRetry, kind: ButtonKind.ghost, expand: false, icon: Icons.refresh),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: AppColors.blueBg, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: AppColors.blue),
          ),
          const SizedBox(height: 16),
          Text(title, style: AppText.headlineMd, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: AppText.bodyMd, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 20),
            AppButton(label: action!, onPressed: onAction, expand: false),
          ],
        ]),
      ),
    );
  }
}

/// Generic loader: shows loading / error+retry / content for a Future.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.future, required this.builder, this.onRetry});
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: onRetry);
        return builder(context, snap.data as T);
      },
    );
  }
}

// ---------------- Helpers ----------------

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      backgroundColor: error ? AppColors.redText : AppColors.navy,
    ));
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String confirm = 'Confirm', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppText.headlineMd),
      content: Text(message, style: AppText.bodyMd),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm, style: TextStyle(color: danger ? AppColors.redText : AppColors.blue, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return ok == true;
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.iconSize = 40});
  final String? url;
  final BoxFit fit;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceLow,
      alignment: Alignment.center,
      child: Icon(Icons.smartphone_rounded, size: iconSize, color: AppColors.muted),
    );
    if (url == null) return placeholder;
    if (url!.startsWith('file://')) {
      // Demo mode: photos are stored on the phone.
      return Image.file(File(url!.substring(7)), fit: fit, errorBuilder: (_, __, ___) => placeholder);
    }
    return Image.network(url!, fit: fit, errorBuilder: (_, __, ___) => placeholder);
  }
}

// ---------------- Demo labelling ----------------

/// Small "DEMO" pill shown next to simulated data.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'DEMO'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.amber)),
      child: Text(label, style: AppText.labelSm.copyWith(color: AppColors.amberText, letterSpacing: 0.8)),
    );
  }
}

/// Full-width notice explaining that the app is running on simulated data.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0x66F59E0B)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.science_outlined, size: 20, color: AppColors.amberText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message ??
                'Demo mode: works offline with sample data stored on this phone. People, phones and registry results are simulated.',
            style: AppText.bodySm.copyWith(color: const Color(0xFF92400E)),
          ),
        ),
      ]),
    );
  }
}
