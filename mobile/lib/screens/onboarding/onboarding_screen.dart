import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth_state.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class _Page {
  final String pillar;
  final IconData icon;
  final String title;
  final String body;
  final String chip;
  final Color tint;
  const _Page(this.pillar, this.icon, this.title, this.body, this.chip, this.tint);
}

const _pages = [
  _Page('Pillar 01', Icons.storefront_rounded, 'Discover Trusted Phones',
      'Browse pre-owned phones whose IMEI is registered to the seller in the DeviceTrust registry, with ownership history you can see.',
      'Registered sellers only', AppColors.blue),
  _Page('Pillar 02', Icons.qr_code_scanner_rounded, 'Verify IMEI Status',
      'Type or scan any IMEI to see whether it is registered or reported stolen in our community registry before you pay a single rupee.',
      'Instant registry check', AppColors.green),
  _Page('Pillar 03', Icons.sync_lock_rounded, 'Transfer Ownership Securely',
      'Ownership only changes when both buyer and seller confirm in the app — and every change is recorded in the device\'s history.',
      'Two-party confirmation', AppColors.navy),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  Future<void> _finish(String route) async {
    await context.read<AuthState>().markOnboardingSeen();
    if (mounted) context.go(route);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              const Icon(Icons.verified_user_rounded, color: AppColors.blue),
              const SizedBox(width: 8),
              Flexible(child: Text('DeviceTrust', style: AppText.headlineMd, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              const Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: StatusBadge('PK Registry', kind: BadgeKind.info))),
              const Spacer(),
              TextButton(onPressed: () => _finish('/login'), child: const Text('Skip')),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: AppShadows.card,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Stack(alignment: Alignment.center, children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(color: p.tint.withAlpha(26), shape: BoxShape.circle),
                        ),
                        Icon(p.icon, size: 64, color: p.tint),
                        Positioned(bottom: 18, child: StatusBadge(p.chip, kind: BadgeKind.success, icon: Icons.check_circle)),
                      ]),
                    ),
                    const SizedBox(height: 40),
                    Text(p.pillar.toUpperCase(), style: AppText.labelSm.copyWith(color: AppColors.blue)),
                    const SizedBox(height: 8),
                    Text(p.title, style: AppText.headlineXl, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(p.body, style: AppText.bodyLg.copyWith(color: AppColors.slate), textAlign: TextAlign.center),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == _index ? AppColors.blue : AppColors.outline, borderRadius: BorderRadius.circular(4)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: AppButton(
              label: last ? 'Get Started' : 'Next',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => last
                  ? _finish('/register')
                  : _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            ),
          ),
          TextButton(onPressed: () => _finish('/login'), child: const Text('Already registered? Log In')),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
