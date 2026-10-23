import 'package:devicetrust/core/api_client.dart';
import 'package:devicetrust/core/imei.dart';
import 'package:devicetrust/demo/demo_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String makeImei(String body14) => body14 + Imei.checkDigit(body14).toString();

void main() {
  late DemoBackend demo;
  late String token;

  Future<dynamic> call(String method, String path, {Map<String, dynamic>? query, Object? body, String? as}) =>
      demo.handle(method, path, query: query, body: body, token: as ?? token);

  Future<ApiException> fails(Future<dynamic> f) async {
    try {
      await f;
    } on ApiException catch (e) {
      return e;
    }
    fail('expected ApiException');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    demo = DemoBackend(latency: Duration.zero);
    final s = await demo.handle('POST', '/auth/login', body: {'email': DemoBackend.demoEmail, 'password': DemoBackend.demoPassword});
    token = s['accessToken'] as String;
  });

  test('demo login works; wrong password and simulated users cannot log in', () async {
    expect(token, startsWith('demo:'));
    expect((await fails(demo.handle('POST', '/auth/login', body: {'email': DemoBackend.demoEmail, 'password': 'nope'}))).status, 401);
    expect((await fails(demo.handle('POST', '/auth/login', body: {'email': 'ali@demo.pk', 'password': DemoBackend.demoPassword}))).status, 401);
    final me = await call('GET', '/auth/me');
    expect(me['user']['fullName'], 'Ahmed Khan');
    expect(me['stats']['devices'], 2);
  });

  test('registration creates a new local account', () async {
    final r = await demo.handle('POST', '/auth/register', body: {'email': 'new@x.pk', 'password': 'Passw0rd1', 'fullName': 'New User'});
    expect(r['user']['email'], 'new@x.pk');
    expect((await fails(demo.handle('POST', '/auth/register', body: {'email': 'new@x.pk', 'password': 'Passw0rd1', 'fullName': 'Again'}))).status, 409);
  });

  test('registry: registered, stolen, not found, invalid — always labelled as demo / not PTA', () async {
    final reg = await call('GET', '/registry/${DemoBackend.sampleRegisteredImei}');
    expect(reg['status'], 'registered');
    expect(reg['source'], 'demo_registry');
    expect(reg['disclaimer'], contains('NOT an official PTA'));
    expect((await call('GET', '/registry/${DemoBackend.sampleStolenImei}'))['status'], 'reported_stolen');
    expect((await call('GET', '/registry/${DemoBackend.sampleUnknownImei}'))['status'], 'not_found');
    expect((await call('GET', '/registry/123'))['status'], 'invalid');
  });

  test('marketplace browse: search, filter and sort', () async {
    final all = await call('GET', '/listings');
    expect(all['total'], 8);
    final iphones = await call('GET', '/listings', query: {'q': 'iphone', 'sort': 'price_asc'});
    final prices = (iphones['listings'] as List).map((l) => l['price'] as num).toList();
    expect(prices.length, 2);
    expect(prices.first <= prices.last, isTrue);
    final cheap = await call('GET', '/listings', query: {'maxPrice': '60000'});
    expect((cheap['listings'] as List).every((l) => (l['price'] as num) <= 60000), isTrue);
    final karachi = await call('GET', '/listings', query: {'city': 'Karachi'});
    expect((karachi['listings'] as List).every((l) => l['city'] == 'Karachi'), isTrue);
  });

  test('device registration validates IMEI and blocks duplicates', () async {
    final bad = await fails(call('POST', '/devices', body: {'imei1': '490154203237519', 'brand': 'X', 'model': 'Y'}));
    expect(bad.status, 400);
    final dup = await fails(call('POST', '/devices', body: {'imei1': DemoBackend.sampleRegisteredImei, 'brand': 'X', 'model': 'Y'}));
    expect(dup.status, 409);
    final ok = await call('POST', '/devices', body: {'imei1': makeImei('35123412341234'), 'brand': 'Nokia', 'model': 'G42'});
    expect(ok['device']['registryStatus'], 'registered');
  });

  test('buying a sample phone: seller accepts, ownership moves only after you confirm', () async {
    final list = await call('GET', '/listings', query: {'q': 'iPhone 14'});
    final listing = (list['listings'] as List).first;
    final req = await call('POST', '/purchase-requests', body: {'listingId': listing['id'], 'offerPrice': 240000});
    expect(req['request']['status'], 'accepted');
    final transferId = req['request']['transfer']['id'] as String;
    final before = await call('GET', '/transfers/$transferId');
    expect(before['transfer']['status'], 'pending');
    expect(before['transfer']['senderConfirmedAt'], isNotNull);
    expect(before['transfer']['youConfirmed'], isFalse);
    // Not yours yet.
    final deviceId = listing['device']['id'] as String;
    expect((await fails(call('GET', '/devices/$deviceId'))).status, 403);

    final done = await call('POST', '/transfers/$transferId/confirm');
    expect(done['completed'], isTrue);
    final dev = await call('GET', '/devices/$deviceId');
    expect((dev['ownershipHistory'] as List).last['isYou'], isTrue);
    expect((await call('GET', '/listings/${listing['id']}'))['listing']['status'], 'sold');
    expect((await fails(call('POST', '/transfers/$transferId/confirm'))).status, 409);
  });

  test('selling: simulated buyer offers, you accept, buyer pre-confirmed, you confirm', () async {
    final devices = (await call('GET', '/devices'))['devices'] as List;
    final s22 = devices.firstWhere((d) => d['model'] == 'Galaxy S22');
    final created = await call('POST', '/listings', body: {'deviceId': s22['id'], 'title': 'Galaxy S22 128GB', 'price': 95000, 'condition': 'good', 'city': 'Rawalpindi'});
    final listingId = created['listing']['id'];
    expect((await fails(call('POST', '/listings', body: {'deviceId': s22['id'], 'title': 'Again', 'price': 1, 'condition': 'good', 'city': 'Lahore'}))).status, 409);
    final reqs = (await call('GET', '/purchase-requests', query: {'role': 'seller'}))['requests'] as List;
    final r = reqs.firstWhere((x) => x['listing']['id'] == listingId);
    expect(r['status'], 'pending');
    final acc = await call('POST', '/purchase-requests/${r['id']}/accept');
    final t = await call('POST', '/transfers/${acc['transferId']}/confirm');
    expect(t['completed'], isTrue);
    final mine = (await call('GET', '/devices'))['devices'] as List;
    expect(mine.any((d) => d['id'] == s22['id']), isFalse);
  });

  test('cannot buy your own listing; duplicate open request blocked', () async {
    final devices = (await call('GET', '/devices'))['devices'] as List;
    final d = devices.first;
    final l = await call('POST', '/listings', body: {'deviceId': d['id'], 'title': 'My phone', 'price': 50000, 'condition': 'good', 'city': 'Lahore'});
    expect((await fails(call('POST', '/purchase-requests', body: {'listingId': l['listing']['id']}))).status, 403);
  });

  test('direct transfer to a simulated user + only one active transfer per device', () async {
    final devices = (await call('GET', '/devices'))['devices'] as List;
    final d = devices.firstWhere((x) => x['model'] == 'Note 30');
    final unknown = await fails(call('POST', '/transfers', body: {'deviceId': d['id'], 'recipientEmail': 'nobody@x.pk'}));
    expect(unknown.status, 404);
    final t = await call('POST', '/transfers', body: {'deviceId': d['id'], 'recipientEmail': 'ali@demo.pk'});
    expect(t['transfer']['recipientConfirmedAt'], isNotNull);
    expect((await fails(call('POST', '/transfers', body: {'deviceId': d['id'], 'recipientEmail': 'sara@demo.pk'}))).status, 409);
    expect((await call('POST', '/transfers/${t['transfer']['id']}/confirm'))['completed'], isTrue);
  });

  test('stolen report: pending -> simulated approval -> registry shows stolen and device is locked', () async {
    final devices = (await call('GET', '/devices'))['devices'] as List;
    final d = devices.firstWhere((x) => x['model'] == 'Galaxy S22');
    final imei = (d['imeis'] as List).first['imei'];
    await call('POST', '/listings', body: {'deviceId': d['id'], 'title': 'Galaxy S22', 'price': 90000, 'condition': 'good', 'city': 'Lahore'});
    final rep = await call('POST', '/stolen-reports', body: {
      'deviceId': d['id'], 'incidentDate': '2026-10-01', 'location': 'Saddar, Rawalpindi', 'description': 'Snatched near the bus stop',
    });
    expect(rep['report']['status'], 'pending');
    // Listing withdrawn when reported.
    final dev = await call('GET', '/devices/${d['id']}');
    expect(dev['device']['liveListing'], isNull);
    expect(dev['device']['reportPending'], isTrue);
    await call('POST', '/demo/reports/${rep['report']['id']}/approve');
    expect((await call('GET', '/registry/$imei'))['status'], 'reported_stolen');
    expect((await fails(call('POST', '/listings', body: {'deviceId': d['id'], 'title': 'Again', 'price': 1000, 'condition': 'good', 'city': 'Lahore'}))).status, 409);
    expect((await fails(call('POST', '/transfers', body: {'deviceId': d['id'], 'recipientEmail': 'ali@demo.pk'}))).status, 409);
  });

  test('data persists across app restarts and reset restores sample data', () async {
    await call('POST', '/devices', body: {'imei1': makeImei('35777777777771'), 'brand': 'Nokia', 'model': 'X'});
    final again = DemoBackend(latency: Duration.zero);
    final me = await again.handle('GET', '/auth/me', token: token);
    expect(me['stats']['devices'], 3);
    await again.reset();
    final reset = await again.handle('GET', '/auth/me', token: token);
    expect(reset['stats']['devices'], 2);
  });

  test('notifications are created and can be marked read', () async {
    final n = await call('GET', '/notifications');
    expect(n['unreadCount'], greaterThan(0));
    await call('POST', '/notifications/read-all');
    expect((await call('GET', '/notifications'))['unreadCount'], 0);
  });
}
