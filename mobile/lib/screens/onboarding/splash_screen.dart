import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/auth_state.dart';
import '../../core/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    // Short brand moment, then restore the session. The router redirects
    // automatically when AuthState.status changes (refreshListenable).
    Future<void>.delayed(const Duration(milliseconds: 900)).then((_) => auth.bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.ink, AppColors.navy]),
        ),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Color(0x66246BFD), blurRadius: 32, offset: Offset(0, 8))],
              ),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            RichText(
              text: TextSpan(style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white), children: const [
                TextSpan(text: 'Device'),
                TextSpan(text: 'Trust', style: TextStyle(color: Color(0xFF6E9BFF))),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Buy Smart. Sell Safely.', style: AppText.bodyLg.copyWith(color: const Color(0xFFB5C7EB))),
            const Spacer(flex: 3),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6E9BFF))),
            const SizedBox(height: 24),
            Text('Karachi • Lahore • Islamabad', style: AppText.labelMd.copyWith(color: const Color(0xFF798BAC))),
            const SizedBox(height: 4),
            Text('v0.7 • Community device registry', style: AppText.monoData.copyWith(color: const Color(0xFF798BAC))),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
