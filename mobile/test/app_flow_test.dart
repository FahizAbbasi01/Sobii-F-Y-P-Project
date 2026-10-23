// End-to-end UI tests: run the real app (router, screens, widgets) against the
// in-app demo backend on a phone-sized screen and tap through the main flows.
import 'package:devicetrust/core/imei.dart';
import 'package:devicetrust/demo/demo_backend.dart';
import 'package:devicetrust/main.dart';
import 'package:devicetrust/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpUntil(WidgetTester t, Finder f, {int tries = 150}) async {
  for (var i = 0; i < tries; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  final visible = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((s) => s.trim().isNotEmpty).take(60).join(' | ');
  throw TestFailure('Timed out waiting for: $f\nVisible text: $visible');
}

Future<void> tapOn(WidgetTester t, Finder f) async {
  await pumpUntil(t, f);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 300));
}

Finder field(String label) =>
    find.descendant(of: find.widgetWithText(AppField, label), matching: find.byType(TextFormField));

Future<void> typeInto(WidgetTester t, String label, String text) async {
  final f = field(label);
  await pumpUntil(t, f);
  await t.ensureVisible(f.first);
  await t.enterText(f.first, text);
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> pickFromDropdown(WidgetTester t, String label, String item) async {
  final dd = find.descendant(of: find.widgetWithText(AppDropdown<String>, label), matching: find.byType(DropdownButtonFormField<String>));
  await tapOn(t, dd);
  await t.pump(const Duration(milliseconds: 500));
  await t.tap(find.text(item).last);
  await t.pump(const Duration(milliseconds: 500));
}

/// Launch the app, skip onboarding and sign in with the demo account.
Future<void> startSignedIn(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2400); // ~393 x 873 dp, a typical Android phone
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(buildApp(demo: DemoBackend(latency: const Duration(milliseconds: 20))));
  await pumpUntil(t, find.text('Discover Trusted Phones'));
  await tapOn(t, find.text('Skip'));
  await pumpUntil(t, find.text('Welcome Back'));
  expect(find.text('Demo account'), findsOneWidget);
  await tapOn(t, find.byKey(const Key('demo-login')));
  await pumpUntil(t, find.text('Find Your Next Phone'));
}

void main() {
  testWidgets('splash, onboarding, demo login and home dashboard', (t) async {
    await startSignedIn(t);
    expect(find.textContaining('Demo mode'), findsOneWidget);
    await pumpUntil(t, find.text('Latest Registered Phones'));
    await pumpUntil(t, find.text('Top Brands'));
    // Notifications screen
    await tapOn(t, find.byTooltip('Notifications'));
    await pumpUntil(t, find.text('Welcome to DeviceTrust (demo)'));
  });

  testWidgets('browse + search, request to buy, confirm transfer, become owner', (t) async {
    await startSignedIn(t);
    await tapOn(t, find.text('Explore'));
    await pumpUntil(t, find.text('8 phones found'));
    final search = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search brand, model…');
    await t.enterText(search, 'iphone 14');
    await t.pump(const Duration(milliseconds: 600));
    await pumpUntil(t, find.text('1 phone found'));
    await tapOn(t, find.text('Apple iPhone 14 Pro'));
    await tapOn(t, find.text('Request to Buy'));
    await tapOn(t, find.text('Send request'));
    await tapOn(t, find.text('Open transfer'));
    await tapOn(t, find.text('Your confirmation needed'));
    await tapOn(t, find.text('Confirm transfer'));
    await tapOn(t, find.text('I confirm'));
    await pumpUntil(t, find.text('View my device'));
    expect(find.text('Completed'), findsWidgets);
    await tapOn(t, find.text('View my device'));
    await pumpUntil(t, find.text('Ownership history'));
    expect(find.textContaining('(current owner)'), findsOneWidget);
  });

  testWidgets('IMEI verification with the sample registry', (t) async {
    await startSignedIn(t);
    await tapOn(t, find.text('Check IMEI'));
    await tapOn(t, find.byKey(const Key('sample-Reported stolen')));
    await pumpUntil(t, find.text('Reported Stolen'));
    expect(find.textContaining('NOT an official PTA'), findsOneWidget);
    await tapOn(t, find.byKey(const Key('sample-Not found')));
    await pumpUntil(t, find.text('Not Found'));
    await tapOn(t, find.byKey(const Key('sample-Registered')));
    await pumpUntil(t, find.textContaining('Apple iPhone 14 Pro'));
    // Invalid input is rejected before any lookup.
    await t.enterText(field('15-digit IMEI'), '490154203237519');
    await tapOn(t, find.text('Verify IMEI'));
    await pumpUntil(t, find.textContaining('Check digit is wrong'));
  });

  testWidgets('register a phone, list it, accept the simulated buyer and transfer it', (t) async {
    await startSignedIn(t);
    await tapOn(t, find.text('Sell'));
    await tapOn(t, find.text('Register a new phone & sell it'));
    final body = '35${DateTime.now().millisecondsSinceEpoch}'.substring(0, 14);
    await typeInto(t, 'IMEI 1', body + Imei.checkDigit(body).toString());
    await pickFromDropdown(t, 'Brand', 'Samsung');
    await typeInto(t, 'Model', 'Galaxy A35');
    await typeInto(t, 'Storage (GB)', '128');
    await tapOn(t, find.byType(CheckboxListTile));
    await tapOn(t, find.text('Register & continue to listing'));
    await pumpUntil(t, find.text('Create Listing'));
    await typeInto(t, 'Price (PKR)', '68000');
    await tapOn(t, find.widgetWithText(ChoiceChip, 'Good'));
    await pickFromDropdown(t, 'City', 'Rawalpindi');
    await tapOn(t, find.text('Publish listing'));
    await tapOn(t, find.text('View requests'));
    await pumpUntil(t, find.textContaining('Sara Malik'));
    await tapOn(t, find.widgetWithText(AppButton, 'Accept'));
    await tapOn(t, find.widgetWithText(TextButton, 'Accept'));
    await tapOn(t, find.text('Confirm transfer'));
    await tapOn(t, find.text('I confirm'));
    await pumpUntil(t, find.text('Completed'));
  });

  testWidgets('report a device stolen and simulate admin approval', (t) async {
    await startSignedIn(t);
    await tapOn(t, find.text('Profile'));
    await tapOn(t, find.text('My devices'));
    await tapOn(t, find.text('Samsung Galaxy S22'));
    await tapOn(t, find.text('Report stolen'));
    await tapOn(t, find.text('Select date'));
    await tapOn(t, find.text('OK'));
    await typeInto(t, 'Where did it happen?', 'Saddar, Rawalpindi');
    await typeInto(t, 'What happened?', 'Snatched near the bus stop in the evening.');
    await tapOn(t, find.text('Submit stolen report'));
    await tapOn(t, find.text('Submit report'));
    await pumpUntil(t, find.text('Your stolen report is being reviewed by an admin.'));
    await tapOn(t, find.text('View'));
    await tapOn(t, find.text('Simulate admin approval'));
    await tapOn(t, find.widgetWithText(TextButton, 'Approve'));
    await pumpUntil(t, find.text('Approved'));
  });

  testWidgets('direct ownership transfer to a simulated user', (t) async {
    await startSignedIn(t);
    await tapOn(t, find.text('Profile'));
    await tapOn(t, find.text('My devices'));
    await tapOn(t, find.text('Infinix Note 30'));
    await tapOn(t, find.text('Transfer ownership directly'));
    await tapOn(t, find.text('ali@demo.pk'));
    await tapOn(t, find.text('Start transfer'));
    await tapOn(t, find.widgetWithText(TextButton, 'Start'));
    await tapOn(t, find.text('Confirm transfer'));
    await tapOn(t, find.text('I confirm'));
    await pumpUntil(t, find.text('Completed'));
  });
}
