import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/imei.dart';

typedef J = Map<String, dynamic>;

/// DEMO MODE backend.
///
/// Implements the same REST endpoints and business rules as the Node/Express
/// server (backend/), but runs entirely inside the app and stores its data on
/// the phone (SharedPreferences). Used for the FYP presentation so the app works
/// without any server or internet connection.
///
/// "Other people" in the flows (sellers, buyers, admins) are simulated:
///  * a purchase request on a sample listing is accepted by the simulated seller;
///  * a new listing you create receives an offer from a simulated buyer;
///  * transfers to simulated users are confirmed by them automatically;
///  * stolen reports can be approved with a "simulate admin review" action.
class DemoBackend {
  DemoBackend({this.latency = const Duration(milliseconds: 250)});

  /// Small artificial delay so loading states are visible, like a real network call.
  final Duration latency;

  static const storageKey = 'devicetrust_demo_db_v1';
  static const demoEmail = 'demo@devicetrust.pk';
  static const demoPassword = 'demo1234';

  static String _imei(String body14) => body14 + Imei.checkDigit(body14).toString();

  /// Sample IMEIs shown on the IMEI check screen for the presentation.
  static final String sampleRegisteredImei = _imei('35467810234561');
  static final String sampleStolenImei = _imei('35209900176148');
  static final String sampleUnknownImei = _imei('86034205118734');

  static const _tables = [
    'users', 'devices', 'imeis', 'history', 'listings', 'requests',
    'transfers', 'reports', 'documents', 'notifications',
  ];

  Map<String, List<J>>? _db;
  int _seq = 0;
  final _rand = Random();

  // ---------------------------------------------------------------- storage

  Future<void> _load() async {
    if (_db != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _db = {
          for (final t in _tables)
            t: ((decoded[t] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        };
        return;
      } catch (_) {
        // Corrupt data: fall through and reseed.
      }
    }
    _db = _seed();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(_db));
  }

  /// Wipes everything and restores the original sample data.
  Future<void> reset() async {
    _db = _seed();
    await _save();
  }

  List<J> _t(String name) => _db![name]!;

  String _id(String prefix) {
    _seq++;
    return '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
  static String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

  // ---------------------------------------------------------------- seed data

  Map<String, List<J>> _seed() {
    final db = {for (final t in _tables) t: <J>[]};

    J user(String id, String email, String name, String city, String phone, int daysAgo) => {
          'id': id, 'email': email, 'fullName': name, 'city': city, 'phone': phone,
          'role': 'user', 'password': demoPassword, 'createdAt': _ago(Duration(days: daysAgo)),
        };
    db['users']!.addAll([
      user('u_demo', demoEmail, 'Ahmed Khan', 'Rawalpindi', '+923001234567', 120),
      user('bot_ali', 'ali@demo.pk', 'Ali Raza', 'Lahore', '+923211112222', 300),
      user('bot_sara', 'sara@demo.pk', 'Sara Malik', 'Karachi', '+923331113333', 210),
      user('bot_bilal', 'bilal@demo.pk', 'Bilal Ahmed', 'Islamabad', '+923451114444', 180),
      user('bot_usman', 'usman@demo.pk', 'Usman Tariq', 'Faisalabad', '+923061115555', 90),
    ]);

    var n = 0;
    String device(String owner, String brand, String model, int? gb, String? color, List<String> imeiBodies,
        {int daysAgo = 60, String status = 'registered', String? previousOwner}) {
      n++;
      final id = 'dev_seed_$n';
      db['devices']!.add({
        'id': id, 'ownerId': owner, 'brand': brand, 'model': model, 'storageGb': gb, 'color': color,
        'registryStatus': status, 'createdAt': _ago(Duration(days: daysAgo)),
      });
      for (var i = 0; i < imeiBodies.length; i++) {
        db['imeis']!.add({'imei': _imei(imeiBodies[i]), 'deviceId': id, 'slot': i + 1});
      }
      if (previousOwner != null) {
        db['history']!.add({
          'id': 'h_${id}_0', 'deviceId': id, 'ownerId': previousOwner, 'acquiredVia': 'registration',
          'transferId': null, 'acquiredAt': _ago(Duration(days: daysAgo)), 'releasedAt': _ago(Duration(days: daysAgo ~/ 2)),
        });
        db['history']!.add({
          'id': 'h_${id}_1', 'deviceId': id, 'ownerId': owner, 'acquiredVia': 'transfer',
          'transferId': null, 'acquiredAt': _ago(Duration(days: daysAgo ~/ 2)), 'releasedAt': null,
        });
      } else {
        db['history']!.add({
          'id': 'h_${id}_0', 'deviceId': id, 'ownerId': owner, 'acquiredVia': 'registration',
          'transferId': null, 'acquiredAt': _ago(Duration(days: daysAgo)), 'releasedAt': null,
        });
      }
      return id;
    }

    var ln = 0;
    void listing(String deviceId, String seller, String title, num price, String condition, String city, String desc, int hoursAgo) {
      ln++;
      db['listings']!.add({
        'id': 'lst_seed_$ln', 'deviceId': deviceId, 'sellerId': seller, 'title': title, 'description': desc,
        'price': price, 'condition': condition, 'city': city, 'status': 'active',
        'createdAt': _ago(Duration(hours: hoursAgo)), 'updatedAt': _ago(Duration(hours: hoursAgo)), 'images': <J>[],
      });
    }

    // Marketplace stock owned by simulated users.
    final d1 = device('bot_ali', 'Apple', 'iPhone 14 Pro', 128, 'Deep Purple', ['35467810234561'], daysAgo: 200);
    listing(d1, 'bot_ali', 'iPhone 14 Pro 128GB PTA approved', 245000, 'like_new', 'Lahore',
        'Battery health 91%. Box and original cable included. No repairs.', 3);
    final d2 = device('bot_sara', 'Samsung', 'Galaxy S23 Ultra', 256, 'Phantom Black', ['35029611456782', '35029611456790'],
        daysAgo: 150, previousOwner: 'bot_usman');
    listing(d2, 'bot_sara', 'Galaxy S23 Ultra 256GB dual SIM', 210000, 'good', 'Karachi',
        'Minor scratch on frame. S-Pen works perfectly. PTA official.', 9);
    final d3 = device('bot_bilal', 'Google', 'Pixel 8', 128, 'Hazel', ['35888702113344'], daysAgo: 95);
    listing(d3, 'bot_bilal', 'Pixel 8 128GB, original camera', 155000, 'good', 'Islamabad',
        'Used for 6 months. Comes with case.', 20);
    final d4 = device('bot_usman', 'Xiaomi', 'Redmi Note 13', 256, 'Midnight Black', ['86915305557712', '86915305557720'], daysAgo: 70);
    listing(d4, 'bot_usman', 'Redmi Note 13 8/256 with box', 56000, 'like_new', 'Faisalabad',
        'Under warranty. All accessories available.', 30);
    final d5 = device('bot_ali', 'Samsung', 'Galaxy A54', 128, 'Awesome Lime', ['35112233445566'], daysAgo: 160);
    listing(d5, 'bot_ali', 'Galaxy A54 128GB', 72000, 'fair', 'Lahore', 'Back glass has a small crack. Works perfectly.', 52);
    final d6 = device('bot_sara', 'OPPO', 'Reno 11', 256, 'Wave Green', ['86120044331122'], daysAgo: 40);
    listing(d6, 'bot_sara', 'OPPO Reno 11 5G, 12/256', 98000, 'new', 'Karachi', 'Box packed, received as gift.', 70);
    final d7 = device('bot_bilal', 'Apple', 'iPhone 12', 64, 'Blue', ['35304611987650'], daysAgo: 400, previousOwner: 'bot_ali');
    listing(d7, 'bot_bilal', 'iPhone 12 64GB JV', 82000, 'good', 'Islamabad', 'Battery 84%. Face ID working.', 96);
    final d8 = device('bot_usman', 'Vivo', 'V29', 256, 'Noble Black', ['86277055664433'], daysAgo: 50);
    listing(d8, 'bot_usman', 'Vivo V29 12/256 PTA', 89000, 'like_new', 'Faisalabad', 'Like new condition.', 120);

    // A device that was reported stolen and approved — used for the "Reported Stolen" demo result.
    final stolen = device('bot_bilal', 'Samsung', 'Galaxy S21', 128, 'Phantom Gray', ['35209900176148'],
        daysAgo: 500, status: 'reported_stolen');
    db['reports']!.add({
      'id': 'rep_seed_1', 'deviceId': stolen, 'reporterId': 'bot_bilal', 'incidentDate': _ago(const Duration(days: 20)).substring(0, 10),
      'location': 'Blue Area, Islamabad', 'description': 'Snatched at a traffic signal. FIR registered.',
      'policeReportNumber': 'FIR-118/26', 'status': 'approved', 'reviewNote': 'Verified (simulated admin review)',
      'reviewedAt': _ago(const Duration(days: 18)), 'createdAt': _ago(const Duration(days: 19)),
    });

    // Devices owned by the demo account (ready to list, transfer or report).
    device('u_demo', 'Samsung', 'Galaxy S22', 128, 'Green', ['35667788990011'], daysAgo: 100);
    device('u_demo', 'Infinix', 'Note 30', 256, 'Black', ['35990011223344', '35990011223352'], daysAgo: 30);

    db['notifications']!.add({
      'id': 'ntf_welcome', 'userId': 'u_demo', 'type': 'system.welcome', 'title': 'Welcome to DeviceTrust (demo)',
      'body': 'You are using the offline demo. All people, phones and results are sample data stored on this phone.',
      'data': <String, dynamic>{}, 'read': false, 'createdAt': _ago(const Duration(minutes: 5)),
    });
    return db;
  }

  // ---------------------------------------------------------------- helpers

  ApiException _err(int status, String code, String message) => ApiException(status, code, message);
  ApiException _bad(String m) => _err(400, 'bad_request', m);
  ApiException _forbidden(String m) => _err(403, 'forbidden', m);
  ApiException _notFound(String m) => _err(404, 'not_found', m);
  ApiException _conflict(String m) => _err(409, 'conflict', m);

  J? _find(String table, String? id) {
    if (id == null) return null;
    for (final r in _t(table)) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  J _user(String id) => _find('users', id) ?? {'id': id, 'fullName': 'Unknown', 'email': '', 'city': null};
  bool _isBot(String userId) => userId.startsWith('bot_');

  String _shortName(String full) {
    final p = full.trim().split(RegExp(r'\s+'));
    return p.length > 1 && p[1].isNotEmpty ? '${p[0]} ${p[1][0]}.' : p[0];
  }

  J _publicUser(J u) => {
        'id': u['id'], 'email': u['email'], 'fullName': u['fullName'], 'phone': u['phone'],
        'city': u['city'], 'role': u['role'], 'createdAt': u['createdAt'],
      };

  void _notify(String userId, String type, String title, String body, [J data = const {}]) {
    _t('notifications').add({
      'id': _id('ntf_'), 'userId': userId, 'type': type, 'title': title, 'body': body,
      'data': Map<String, dynamic>.from(data), 'read': false, 'createdAt': _now(),
    });
  }

  J _requireUser(String? token) {
    if (token == null || !token.startsWith('demo:')) throw _err(401, 'unauthorized', 'Please sign in.');
    final u = _find('users', token.substring(5));
    if (u == null) throw _err(401, 'unauthorized', 'Session expired. Please sign in again.');
    return u;
  }

  J? _optionalUser(String? token) {
    if (token == null || !token.startsWith('demo:')) return null;
    return _find('users', token.substring(5));
  }

  num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
  String _str(dynamic v) => (v ?? '').toString().trim();

  List<J> _imeisOf(String deviceId) {
    final list = _t('imeis').where((i) => i['deviceId'] == deviceId).toList()
      ..sort((a, b) => (a['slot'] as num).compareTo(b['slot'] as num));
    return list;
  }

  J? _liveListing(String deviceId) {
    for (final l in _t('listings')) {
      if (l['deviceId'] == deviceId && (l['status'] == 'active' || l['status'] == 'reserved')) return l;
    }
    return null;
  }

  J? _pendingTransfer(String deviceId) {
    for (final t in _t('transfers')) {
      if (t['deviceId'] == deviceId && t['status'] == 'pending') return t;
    }
    return null;
  }

  bool _reportPending(String deviceId) => _t('reports').any((r) => r['deviceId'] == deviceId && r['status'] == 'pending');

  J _deviceOr404(String id) => _find('devices', id) ?? (throw _notFound('Device not found'));

  void _assertNotStolen(J d) {
    if (d['registryStatus'] == 'reported_stolen') {
      throw _err(409, 'device_stolen', 'This device is reported stolen and cannot be sold or transferred');
    }
  }

  J _deviceDto(J d) {
    final live = _liveListing(d['id'] as String);
    return {
      'id': d['id'], 'brand': d['brand'], 'model': d['model'], 'storageGb': d['storageGb'], 'color': d['color'],
      'registryStatus': d['registryStatus'],
      'imeis': _imeisOf(d['id'] as String).map((i) => {'imei': i['imei'], 'slot': i['slot']}).toList(),
      'liveListing': live == null ? null : {'id': live['id'], 'status': live['status'], 'price': live['price']},
      'pendingTransferId': _pendingTransfer(d['id'] as String)?['id'],
      'reportPending': _reportPending(d['id'] as String),
      'registeredAt': d['createdAt'],
    };
  }

  J _listingDto(J l, {bool detail = false}) {
    final d = _find('devices', l['deviceId'] as String)!;
    final s = _user(l['sellerId'] as String);
    final imeis = _imeisOf(d['id'] as String);
    final images = ((l['images'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final dto = <String, dynamic>{
      'id': l['id'], 'title': l['title'], 'price': l['price'], 'condition': l['condition'], 'city': l['city'],
      'status': l['status'], 'createdAt': l['createdAt'], 'updatedAt': l['updatedAt'],
      'images': (detail ? images : images.take(1)).map((i) => {'id': i['id'], 'url': 'file://${i['path']}'}).toList(),
      'device': {
        'id': d['id'], 'brand': d['brand'], 'model': d['model'], 'storageGb': d['storageGb'], 'color': d['color'],
        'registryStatus': d['registryStatus'],
        'imeiLast4': imeis.isEmpty ? null : (imeis.first['imei'] as String).substring(11),
        'ownerCount': _t('history').where((h) => h['deviceId'] == d['id']).length,
      },
      'seller': {
        'id': s['id'], 'name': s['fullName'], 'city': s['city'], 'memberSince': s['createdAt'],
        'soldCount': _t('listings').where((x) => x['sellerId'] == s['id'] && x['status'] == 'sold').length,
      },
    };
    if (detail) dto['description'] = l['description'];
    return dto;
  }

  J _requestDto(J r, String meId) {
    final l = _find('listings', r['listingId'] as String)!;
    final d = _find('devices', l['deviceId'] as String)!;
    final b = _user(r['buyerId'] as String);
    final s = _user(l['sellerId'] as String);
    J? t;
    for (final x in _t('transfers').reversed) {
      if (x['purchaseRequestId'] == r['id']) {
        t = x;
        break;
      }
    }
    return {
      'id': r['id'], 'status': r['status'], 'offerPrice': r['offerPrice'], 'message': r['message'],
      'createdAt': r['createdAt'], 'updatedAt': r['updatedAt'],
      'role': r['buyerId'] == meId ? 'buyer' : 'seller',
      'listing': {'id': l['id'], 'title': l['title'], 'price': l['price'], 'status': l['status']},
      'device': {'id': d['id'], 'brand': d['brand'], 'model': d['model'], 'storageGb': d['storageGb']},
      'buyer': {'id': b['id'], 'name': b['fullName'], 'city': b['city']},
      'seller': {'id': s['id'], 'name': s['fullName']},
      'transfer': t == null ? null : {'id': t['id'], 'status': t['status']},
    };
  }

  J _transferDto(J t, String meId) {
    final d = _find('devices', t['deviceId'] as String)!;
    final f = _user(t['fromId'] as String);
    final to = _user(t['toId'] as String);
    final role = t['fromId'] == meId ? 'sender' : 'recipient';
    final imeis = _imeisOf(d['id'] as String);
    return {
      'id': t['id'], 'status': t['status'], 'role': role,
      'device': {
        'id': d['id'], 'brand': d['brand'], 'model': d['model'], 'storageGb': d['storageGb'],
        'imeiLast4': imeis.isEmpty ? null : (imeis.first['imei'] as String).substring(11),
        'registryStatus': d['registryStatus'],
      },
      'from': {'id': f['id'], 'name': f['fullName']},
      'to': {'id': to['id'], 'name': to['fullName'], 'email': role == 'sender' ? to['email'] : null},
      'purchaseRequestId': t['purchaseRequestId'],
      'senderConfirmedAt': t['senderConfirmedAt'],
      'recipientConfirmedAt': t['recipientConfirmedAt'],
      'youConfirmed': role == 'sender' ? t['senderConfirmedAt'] != null : t['recipientConfirmedAt'] != null,
      'createdAt': t['createdAt'], 'completedAt': t['completedAt'],
    };
  }

  J _reportDto(J r) {
    final d = _find('devices', r['deviceId'] as String);
    return {
      'id': r['id'], 'deviceId': r['deviceId'],
      'device': d == null ? null : {'brand': d['brand'], 'model': d['model']},
      'incidentDate': r['incidentDate'], 'location': r['location'], 'description': r['description'],
      'policeReportNumber': r['policeReportNumber'], 'status': r['status'], 'reviewNote': r['reviewNote'],
      'reviewedAt': r['reviewedAt'], 'createdAt': r['createdAt'],
    };
  }

  // ---------------------------------------------------------------- entry point

  /// Handles one API call. Mirrors the HTTP API paths used by the app (without the /api/v1 prefix).
  Future<dynamic> handle(String method, String path,
      {Map<String, dynamic>? query, Object? body, List<UploadFile> files = const [], Map<String, String> fields = const {}, String? token}) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    await _load();
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    final b = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
    final seg = path.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty) throw _notFound('No route');

    final result = switch (seg[0]) {
      'auth' => _auth(method, seg, b, token),
      'registry' => _registry(seg, token),
      'devices' => _devices(method, seg, b, token),
      'listings' => _listings(method, seg, q, b, files, token),
      'purchase-requests' => _purchases(method, seg, q, b, token),
      'transfers' => _transfers(method, seg, q, b, token),
      'stolen-reports' => _reports(method, seg, b, token),
      'documents' => _documents(method, files, fields, token),
      'notifications' => _notifications(method, seg, q, token),
      'demo' => _demoActions(method, seg, token),
      _ => throw _notFound('No route for $method $path'),
    };
    if (method != 'GET') await _save();
    return result;
  }

  // ---------------------------------------------------------------- auth

  dynamic _auth(String method, List<String> seg, J b, String? token) {
    final action = seg.length > 1 ? seg[1] : '';
    if (method == 'POST' && action == 'register') {
      final email = _str(b['email']).toLowerCase();
      final name = _str(b['fullName']);
      final password = (b['password'] ?? '').toString();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) throw _bad('email: Enter a valid email');
      if (name.length < 2) throw _bad('fullName: Enter your full name');
      if (password.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'[0-9]').hasMatch(password)) {
        throw _bad('password: Use at least 8 characters with letters and numbers');
      }
      if (_t('users').any((u) => u['email'] == email)) throw _conflict('An account with this email already exists');
      final u = {
        'id': _id('u_'), 'email': email, 'fullName': name, 'phone': b['phone'], 'city': b['city'],
        'role': 'user', 'password': password, 'createdAt': _now(),
      };
      _t('users').add(u);
      _notify(u['id'] as String, 'system.welcome', 'Welcome to DeviceTrust (demo)',
          'Your demo account is stored only on this phone. Register a phone to get started.');
      return _session(u);
    }
    if (method == 'POST' && action == 'login') {
      final email = _str(b['email']).toLowerCase();
      J? u;
      for (final x in _t('users')) {
        if (x['email'] == email) u = x;
      }
      if (u == null || u['password'] != b['password'] || _isBot(u['id'] as String)) {
        throw _err(401, 'unauthorized', 'Incorrect email or password');
      }
      return _session(u);
    }
    if (method == 'POST' && action == 'refresh') {
      final rt = _str(b['refreshToken']);
      final u = rt.startsWith('demo-refresh:') ? _find('users', rt.substring(13)) : null;
      if (u == null) throw _err(401, 'unauthorized', 'Session expired. Please sign in again.');
      return _session(u);
    }
    if (method == 'POST' && action == 'logout') return null;

    final me = _requireUser(token);
    if (method == 'GET' && action == 'me') {
      final id = me['id'];
      return {
        'user': _publicUser(me),
        'stats': {
          'devices': _t('devices').where((d) => d['ownerId'] == id).length,
          'activeListings': _t('listings').where((l) => l['sellerId'] == id && (l['status'] == 'active' || l['status'] == 'reserved')).length,
          'unreadNotifications': _t('notifications').where((n) => n['userId'] == id && n['read'] != true).length,
        },
      };
    }
    if (method == 'PATCH' && action == 'me') {
      if (b.containsKey('fullName')) {
        final n = _str(b['fullName']);
        if (n.length < 2) throw _bad('fullName: Enter your name');
        me['fullName'] = n;
      }
      if (b.containsKey('phone')) me['phone'] = b['phone'];
      if (b.containsKey('city')) me['city'] = b['city'];
      return {'user': _publicUser(me)};
    }
    if (method == 'POST' && action == 'change-password') {
      if (b['currentPassword'] != me['password']) throw _bad('Current password is incorrect');
      final np = (b['newPassword'] ?? '').toString();
      if (np.length < 8) throw _bad('New password must be at least 8 characters');
      me['password'] = np;
      return {'accessToken': 'demo:${me['id']}', 'refreshToken': 'demo-refresh:${me['id']}'};
    }
    throw _notFound('No route');
  }

  J _session(J u) => {'user': _publicUser(u), 'accessToken': 'demo:${u['id']}', 'refreshToken': 'demo-refresh:${u['id']}'};

  // ---------------------------------------------------------------- registry

  J _registry(List<String> seg, String? token) {
    const disclaimer = 'DEMO DATA: this result comes from the sample DeviceTrust registry stored in this app. '
        'It is NOT an official PTA/DIRBS check. For official PTA status, SMS the 15-digit IMEI to 8484.';
    final raw = seg.length > 1 ? seg[1] : '';
    final err = Imei.validate(raw);
    final imei = Imei.normalize(raw);
    if (err != null) return {'imei': imei, 'status': 'invalid', 'reason': err, 'source': 'demo_registry', 'disclaimer': disclaimer};
    J? entry;
    for (final i in _t('imeis')) {
      if (i['imei'] == imei) entry = i;
    }
    final d = entry == null ? null : _find('devices', entry['deviceId'] as String);
    final me = _optionalUser(token);
    final live = d == null ? null : _liveListing(d['id'] as String);
    return {
      'imei': imei,
      'status': d == null ? 'not_found' : d['registryStatus'],
      'source': 'demo_registry',
      'checkedAt': _now(),
      'device': d == null
          ? null
          : {
              'brand': d['brand'], 'model': d['model'], 'storageGb': d['storageGb'], 'registeredSince': d['createdAt'],
              'ownerCount': _t('history').where((h) => h['deviceId'] == d['id']).length,
              'reportUnderReview': _reportPending(d['id'] as String),
              'activeListingId': live != null && live['status'] == 'active' ? live['id'] : null,
              'ownedByYou': me != null && me['id'] == d['ownerId'],
            },
      'disclaimer': disclaimer,
    };
  }

  // ---------------------------------------------------------------- devices

  dynamic _devices(String method, List<String> seg, J b, String? token) {
    final me = _requireUser(token);
    if (seg.length == 1 && method == 'POST') {
      final e1 = Imei.validate(_str(b['imei1']));
      if (e1 != null) throw _bad('IMEI 1: $e1');
      final imeis = [Imei.normalize(_str(b['imei1']))];
      if (_str(b['imei2']).isNotEmpty) {
        final e2 = Imei.validate(_str(b['imei2']));
        if (e2 != null) throw _bad('IMEI 2: $e2');
        final i2 = Imei.normalize(_str(b['imei2']));
        if (i2 == imeis.first) throw _bad('IMEI 1 and IMEI 2 must be different');
        imeis.add(i2);
      }
      for (final i in imeis) {
        if (_t('imeis').any((x) => x['imei'] == i)) throw _err(409, 'imei_taken', 'IMEI $i is already registered in DeviceTrust');
      }
      final brand = _str(b['brand']);
      final model = _str(b['model']);
      if (brand.isEmpty || model.isEmpty) throw _bad('Brand and model are required');
      final id = _id('dev_');
      final d = {
        'id': id, 'ownerId': me['id'], 'brand': brand, 'model': model, 'storageGb': _num(b['storageGb'])?.toInt(),
        'color': _str(b['color']).isEmpty ? null : _str(b['color']), 'registryStatus': 'registered', 'createdAt': _now(),
      };
      _t('devices').add(d);
      for (var i = 0; i < imeis.length; i++) {
        _t('imeis').add({'imei': imeis[i], 'deviceId': id, 'slot': i + 1});
      }
      _t('history').add({'id': _id('h_'), 'deviceId': id, 'ownerId': me['id'], 'acquiredVia': 'registration', 'transferId': null, 'acquiredAt': _now(), 'releasedAt': null});
      return {'device': _deviceDto(d)};
    }
    if (seg.length == 1 && method == 'GET') {
      final mine = _t('devices').where((d) => d['ownerId'] == me['id']).toList()
        ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return {'devices': mine.map(_deviceDto).toList()};
    }
    final d = _deviceOr404(seg[1]);
    if (d['ownerId'] != me['id']) throw _forbidden('You do not own this device');
    if (method == 'GET') {
      final hist = _t('history').where((h) => h['deviceId'] == d['id']).toList()
        ..sort((a, b) => (a['acquiredAt'] as String).compareTo(b['acquiredAt'] as String));
      return {
        'device': _deviceDto(d),
        'ownershipHistory': hist.map((h) {
          final u = _user(h['ownerId'] as String);
          return {
            'ownerName': _shortName(u['fullName'] as String), 'isYou': h['ownerId'] == me['id'],
            'acquiredVia': h['acquiredVia'], 'acquiredAt': h['acquiredAt'], 'releasedAt': h['releasedAt'],
          };
        }).toList(),
      };
    }
    if (method == 'PATCH') {
      _assertNotStolen(d);
      if (b.containsKey('storageGb')) d['storageGb'] = _num(b['storageGb'])?.toInt();
      if (b.containsKey('color')) d['color'] = b['color'];
      return {'device': _deviceDto(d)};
    }
    throw _notFound('No route');
  }

  // ---------------------------------------------------------------- listings

  dynamic _listings(String method, List<String> seg, Map<String, String> q, J b, List<UploadFile> files, String? token) {
    if (method == 'GET' && seg.length == 1) return _browse(q);
    if (method == 'GET' && seg.length == 2 && seg[1] == 'brands') {
      final counts = <String, int>{};
      for (final l in _t('listings').where((l) => l['status'] == 'active')) {
        final d = _find('devices', l['deviceId'] as String)!;
        counts[d['brand'] as String] = (counts[d['brand']] ?? 0) + 1;
      }
      final list = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
      return {'brands': list.map((e) => {'name': e.key, 'count': e.value}).toList()};
    }
    if (method == 'GET' && seg.length == 2 && seg[1] == 'mine') {
      final me = _requireUser(token);
      final mine = _t('listings').where((l) => l['sellerId'] == me['id']).toList()
        ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return {
        'listings': mine.map((l) {
          final dto = _listingDto(l);
          dto['pendingRequests'] = _t('requests').where((r) => r['listingId'] == l['id'] && r['status'] == 'pending').length;
          return dto;
        }).toList(),
      };
    }
    if (method == 'GET' && seg.length == 2) {
      final me = _optionalUser(token);
      final l = _find('listings', seg[1]);
      final isSeller = me != null && l != null && l['sellerId'] == me['id'];
      if (l == null || ((l['status'] == 'withdrawn' || l['status'] == 'removed') && !isSeller)) throw _notFound('Listing not found');
      J? myReq;
      if (me != null && !isSeller) {
        for (final r in _t('requests')) {
          if (r['listingId'] == l['id'] && r['buyerId'] == me['id']) myReq = r;
        }
      }
      return {
        'listing': _listingDto(l, detail: true),
        'isSeller': isSeller,
        'myRequest': myReq == null ? null : {'id': myReq['id'], 'status': myReq['status'], 'offerPrice': myReq['offerPrice']},
      };
    }

    final me = _requireUser(token);
    if (method == 'POST' && seg.length == 1) {
      final d = _deviceOr404(_str(b['deviceId']));
      if (d['ownerId'] != me['id']) throw _forbidden('You do not own this device');
      _assertNotStolen(d);
      if (_pendingTransfer(d['id'] as String) != null) throw _err(409, 'transfer_pending', 'This device has a transfer in progress');
      if (_reportPending(d['id'] as String)) throw _err(409, 'report_pending', 'This device has a stolen report under review');
      if (_liveListing(d['id'] as String) != null) throw _conflict('This device already has a live listing');
      final err = _validateListing(b, partial: false);
      if (err != null) throw _bad(err);
      final l = {
        'id': _id('lst_'), 'deviceId': d['id'], 'sellerId': me['id'], 'title': _str(b['title']),
        'description': _str(b['description']).isEmpty ? null : _str(b['description']),
        'price': _num(b['price']), 'condition': b['condition'], 'city': _str(b['city']), 'status': 'active',
        'createdAt': _now(), 'updatedAt': _now(), 'images': <J>[],
      };
      _t('listings').add(l);
      _simulateBuyerOffer(l, d);
      return {'listing': _listingDto(l, detail: true)};
    }
    final l = _find('listings', seg[1]) ?? (throw _notFound('Listing not found'));
    if (l['sellerId'] != me['id']) throw _forbidden('This is not your listing');
    if (method == 'PATCH' && seg.length == 2) {
      if (l['status'] != 'active') throw _conflict('Only active listings can be edited');
      final err = _validateListing(b, partial: true);
      if (err != null) throw _bad(err);
      for (final k in ['title', 'price', 'condition', 'city', 'description']) {
        if (b.containsKey(k)) l[k] = k == 'price' ? _num(b[k]) : b[k];
      }
      l['updatedAt'] = _now();
      return {'listing': _listingDto(l, detail: true)};
    }
    if (method == 'POST' && seg.length == 3 && seg[2] == 'withdraw') {
      if (l['status'] != 'active') throw _conflict('Only active listings can be withdrawn. Cancel the pending transfer first.');
      l['status'] = 'withdrawn';
      for (final r in _t('requests').where((r) => r['listingId'] == l['id'] && r['status'] == 'pending')) {
        r['status'] = 'rejected';
      }
      return {'ok': true};
    }
    if (method == 'POST' && seg.length == 3 && seg[2] == 'images') {
      if (files.isEmpty) throw _bad('Attach at least one image');
      final images = (l['images'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (images.length + files.length > 6) throw _bad('A listing can have at most 6 images');
      final added = <J>[];
      for (final f in files) {
        final img = {'id': _id('img_'), 'path': f.path};
        images.add(img);
        added.add({'id': img['id'], 'url': 'file://${f.path}'});
      }
      l['images'] = images;
      return {'images': added};
    }
    if (method == 'DELETE' && seg.length == 4 && seg[2] == 'images') {
      final images = (l['images'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      images.removeWhere((i) => i['id'] == seg[3]);
      l['images'] = images;
      return null;
    }
    throw _notFound('No route');
  }

  String? _validateListing(J b, {required bool partial}) {
    bool has(String k) => b.containsKey(k) && b[k] != null;
    if (!partial || has('title')) {
      if (_str(b['title']).length < 3) return 'title: At least 3 characters';
    }
    if (!partial || has('price')) {
      final p = _num(b['price']);
      if (p == null || p <= 0 || p >= 100000000) return 'price: Enter a valid price';
    }
    if (!partial || has('condition')) {
      if (!const ['new', 'like_new', 'good', 'fair', 'poor'].contains(b['condition'])) return 'condition: Choose a condition';
    }
    if (!partial || has('city')) {
      if (_str(b['city']).length < 2) return 'city: Choose a city';
    }
    return null;
  }

  J _browse(Map<String, String> q) {
    final text = (q['q'] ?? '').toLowerCase();
    final minPrice = num.tryParse(q['minPrice'] ?? '');
    final maxPrice = num.tryParse(q['maxPrice'] ?? '');
    final minStorage = int.tryParse(q['minStorage'] ?? '');
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) throw _bad('minPrice cannot exceed maxPrice');
    final rows = _t('listings').where((l) {
      if (l['status'] != 'active') return false;
      final d = _find('devices', l['deviceId'] as String)!;
      if (d['registryStatus'] != 'registered') return false;
      final brand = (d['brand'] as String).toLowerCase();
      final model = (d['model'] as String).toLowerCase();
      if (text.isNotEmpty &&
          !(l['title'] as String).toLowerCase().contains(text) &&
          !brand.contains(text) &&
          !model.contains(text) &&
          !'$brand $model'.contains(text)) {
        return false;
      }
      if ((q['brand'] ?? '').isNotEmpty && brand != q['brand']!.toLowerCase()) return false;
      if ((q['condition'] ?? '').isNotEmpty && l['condition'] != q['condition']) return false;
      if ((q['city'] ?? '').isNotEmpty && (l['city'] as String).toLowerCase() != q['city']!.toLowerCase()) return false;
      final price = _num(l['price']) ?? 0;
      if (minPrice != null && price < minPrice) return false;
      if (maxPrice != null && price > maxPrice) return false;
      if (minStorage != null && ((d['storageGb'] as num?) ?? 0) < minStorage) return false;
      return true;
    }).toList();
    int byDate(J a, J b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String);
    num price(J x) => _num(x['price']) ?? 0;
    switch (q['sort'] ?? 'newest') {
      case 'price_asc':
        rows.sort((a, b) => price(a) != price(b) ? price(a).compareTo(price(b)) : byDate(a, b));
      case 'price_desc':
        rows.sort((a, b) => price(a) != price(b) ? price(b).compareTo(price(a)) : byDate(a, b));
      case 'oldest':
        rows.sort((a, b) => byDate(b, a));
      default:
        rows.sort(byDate);
    }
    final page = max(1, int.tryParse(q['page'] ?? '') ?? 1);
    final limit = (int.tryParse(q['limit'] ?? '') ?? 20).clamp(1, 50);
    final start = (page - 1) * limit;
    final slice = start >= rows.length ? <J>[] : rows.sublist(start, min(rows.length, start + limit));
    return {'listings': slice.map((l) => _listingDto(l)).toList(), 'page': page, 'limit': limit, 'total': rows.length};
  }

  /// Simulated buyer makes an offer on a listing created by a real (non-simulated) user.
  void _simulateBuyerOffer(J listing, J device) {
    if (_isBot(listing['sellerId'] as String)) return;
    final buyer = _user('bot_sara');
    final price = (_num(listing['price']) ?? 0).toDouble();
    final offer = max(500, ((price * 0.95) / 500).round() * 500);
    final r = {
      'id': _id('pr_'), 'listingId': listing['id'], 'buyerId': buyer['id'], 'offerPrice': offer,
      'message': 'Salam! Is it still available? I can meet at a mobile market this weekend. (simulated buyer)',
      'status': 'pending', 'createdAt': _now(), 'updatedAt': _now(),
    };
    _t('requests').add(r);
    _notify(listing['sellerId'] as String, 'purchase.new', 'New purchase request (demo buyer)',
        '${buyer['fullName']} offered PKR ${offer.toString()} for your ${device['brand']} ${device['model']}.',
        {'purchaseRequestId': r['id'], 'listingId': listing['id']});
  }

  // ---------------------------------------------------------------- purchases

  dynamic _purchases(String method, List<String> seg, Map<String, String> q, J b, String? token) {
    final me = _requireUser(token);
    final meId = me['id'] as String;
    if (method == 'POST' && seg.length == 1) {
      final l = _find('listings', _str(b['listingId'])) ?? (throw _notFound('Listing not found'));
      final d = _find('devices', l['deviceId'] as String)!;
      if (l['sellerId'] == meId) throw _forbidden('You cannot buy your own listing');
      if (l['status'] != 'active') throw _err(409, 'listing_unavailable', 'This listing is no longer available');
      _assertNotStolen(d);
      if (_t('requests').any((r) => r['listingId'] == l['id'] && r['buyerId'] == meId && (r['status'] == 'pending' || r['status'] == 'accepted'))) {
        throw _conflict('You already have an open request for this listing');
      }
      final offer = _num(b['offerPrice']) ?? _num(l['price']);
      if (offer == null || offer <= 0) throw _bad('Enter a valid offer');
      final r = {
        'id': _id('pr_'), 'listingId': l['id'], 'buyerId': meId, 'offerPrice': offer,
        'message': _str(b['message']).isEmpty ? null : _str(b['message']), 'status': 'pending',
        'createdAt': _now(), 'updatedAt': _now(),
      };
      _t('requests').add(r);
      if (_isBot(l['sellerId'] as String)) {
        // Simulated seller accepts straight away and confirms their side of the handoff.
        final t = _accept(r, l, d);
        t['senderConfirmedAt'] = _now();
        final seller = _user(l['sellerId'] as String);
        _notify(meId, 'purchase.accepted', 'Request accepted (demo seller)',
            '${seller['fullName']} accepted your offer for the ${d['brand']} ${d['model']} and confirmed the handoff. Confirm the transfer to become the owner.',
            {'purchaseRequestId': r['id'], 'transferId': t['id']});
      } else {
        _notify(l['sellerId'] as String, 'purchase.new', 'New purchase request',
            '${me['fullName']} wants to buy your ${d['brand']} ${d['model']}.', {'purchaseRequestId': r['id'], 'listingId': l['id']});
      }
      return {'request': _requestDto(r, meId)};
    }
    if (method == 'GET' && seg.length == 1) {
      final role = q['role'] ?? 'all';
      final rows = _t('requests').where((r) {
        final l = _find('listings', r['listingId'] as String)!;
        final asBuyer = r['buyerId'] == meId;
        final asSeller = l['sellerId'] == meId;
        return role == 'buyer' ? asBuyer : role == 'seller' ? asSeller : (asBuyer || asSeller);
      }).toList()
        ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return {'requests': rows.map((r) => _requestDto(r, meId)).toList()};
    }
    final r = _find('requests', seg[1]) ?? (throw _notFound('Request not found'));
    final l = _find('listings', r['listingId'] as String)!;
    final d = _find('devices', l['deviceId'] as String)!;
    if (r['buyerId'] != meId && l['sellerId'] != meId) throw _notFound('Request not found');
    if (method == 'GET' && seg.length == 2) return {'request': _requestDto(r, meId)};
    final action = seg.length > 2 ? seg[2] : '';
    if (action == 'accept') {
      if (l['sellerId'] != meId) throw _forbidden('Only the seller can accept this request');
      if (r['status'] != 'pending') throw _conflict('This request is already ${r['status']}');
      if (l['status'] != 'active') throw _conflict('This listing is no longer active');
      if (d['ownerId'] != meId) throw _err(409, 'ownership_changed', 'You no longer own this device');
      _assertNotStolen(d);
      if (_pendingTransfer(d['id'] as String) != null) throw _err(409, 'transfer_pending', 'This device already has a transfer in progress');
      final t = _accept(r, l, d);
      if (_isBot(r['buyerId'] as String)) {
        t['recipientConfirmedAt'] = _now();
        _notify(meId, 'transfer.confirm_needed', 'Buyer confirmed (demo)',
            '${_user(r['buyerId'] as String)['fullName']} received the phone and confirmed. Confirm to complete the transfer.', {'transferId': t['id']});
      }
      return {'request': _requestDto(r, meId), 'transferId': t['id']};
    }
    if (action == 'reject') {
      if (l['sellerId'] != meId) throw _forbidden('Only the seller can reject this request');
      if (r['status'] != 'pending') throw _conflict('This request is already ${r['status']}');
      r['status'] = 'rejected';
      r['updatedAt'] = _now();
      return {'ok': true};
    }
    if (action == 'cancel') {
      if (r['buyerId'] != meId) throw _forbidden('Only the buyer can cancel this request');
      if (r['status'] == 'pending') {
        r['status'] = 'cancelled';
      } else if (r['status'] == 'accepted') {
        J? t;
        for (final x in _t('transfers')) {
          if (x['purchaseRequestId'] == r['id'] && x['status'] == 'pending') t = x;
        }
        if (t == null) throw _conflict('This request can no longer be cancelled');
        _cancelTransfer(t, meId, 'The buyer withdrew their purchase request.');
      } else {
        throw _conflict('This request is already ${r['status']}');
      }
      r['updatedAt'] = _now();
      return {'ok': true};
    }
    throw _notFound('No route');
  }

  /// Seller accepts: request accepted, listing reserved, pending transfer created.
  J _accept(J r, J l, J d) {
    r['status'] = 'accepted';
    r['updatedAt'] = _now();
    l['status'] = 'reserved';
    final t = {
      'id': _id('tr_'), 'deviceId': d['id'], 'fromId': l['sellerId'], 'toId': r['buyerId'], 'purchaseRequestId': r['id'],
      'status': 'pending', 'senderConfirmedAt': null, 'recipientConfirmedAt': null, 'createdAt': _now(), 'completedAt': null,
    };
    _t('transfers').add(t);
    return t;
  }

  // ---------------------------------------------------------------- transfers

  dynamic _transfers(String method, List<String> seg, Map<String, String> q, J b, String? token) {
    final me = _requireUser(token);
    final meId = me['id'] as String;
    if (method == 'POST' && seg.length == 1) {
      final d = _deviceOr404(_str(b['deviceId']));
      if (d['ownerId'] != meId) throw _forbidden('You do not own this device');
      _assertNotStolen(d);
      if (_reportPending(d['id'] as String)) throw _err(409, 'report_pending', 'This device has a stolen report under review');
      if (_liveListing(d['id'] as String) != null) {
        throw _err(409, 'listing_live', 'Withdraw the marketplace listing for this device before transferring it directly');
      }
      if (_pendingTransfer(d['id'] as String) != null) throw _conflict('This device already has a transfer in progress');
      final email = _str(b['recipientEmail']).toLowerCase();
      J? to;
      for (final u in _t('users')) {
        if (u['email'] == email) to = u;
      }
      if (to == null) {
        throw _notFound('No DeviceTrust user with that email. In the demo, try ali@demo.pk, sara@demo.pk, bilal@demo.pk or usman@demo.pk');
      }
      if (to['id'] == meId) throw _bad('You already own this device');
      final t = {
        'id': _id('tr_'), 'deviceId': d['id'], 'fromId': meId, 'toId': to['id'], 'purchaseRequestId': null,
        'status': 'pending', 'senderConfirmedAt': null, 'recipientConfirmedAt': null, 'createdAt': _now(), 'completedAt': null,
      };
      _t('transfers').add(t);
      if (_isBot(to['id'] as String)) {
        t['recipientConfirmedAt'] = _now();
        _notify(meId, 'transfer.confirm_needed', 'Recipient confirmed (demo)',
            '${to['fullName']} accepted the ${d['brand']} ${d['model']}. Confirm to complete the transfer.', {'transferId': t['id']});
      } else {
        _notify(to['id'] as String, 'transfer.incoming', 'Incoming ownership transfer',
            '${me['fullName']} wants to transfer a ${d['brand']} ${d['model']} to you.', {'transferId': t['id']});
      }
      return {'transfer': _transferDto(t, meId)};
    }
    if (method == 'GET' && seg.length == 1) {
      final rows = _t('transfers').where((t) {
        if (t['fromId'] != meId && t['toId'] != meId) return false;
        return (q['status'] ?? '').isEmpty || t['status'] == q['status'];
      }).toList()
        ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return {'transfers': rows.map((t) => _transferDto(t, meId)).toList()};
    }
    final t = _find('transfers', seg[1]) ?? (throw _notFound('Transfer not found'));
    if (t['fromId'] != meId && t['toId'] != meId) throw _notFound('Transfer not found');
    if (method == 'GET' && seg.length == 2) return {'transfer': _transferDto(t, meId)};
    final action = seg.length > 2 ? seg[2] : '';
    final d = _find('devices', t['deviceId'] as String)!;
    if (action == 'confirm') {
      if (t['status'] != 'pending') throw _conflict('This transfer is ${t['status']}');
      _assertNotStolen(d);
      final isSender = t['fromId'] == meId;
      final col = isSender ? 'senderConfirmedAt' : 'recipientConfirmedAt';
      if (t[col] != null) throw _conflict('You have already confirmed this transfer');
      t[col] = _now();
      var completed = false;
      if (t['senderConfirmedAt'] != null && t['recipientConfirmedAt'] != null) {
        _complete(t, d);
        completed = true;
      }
      return {'completed': completed, 'transfer': _transferDto(t, meId)};
    }
    if (action == 'cancel') {
      if (t['status'] != 'pending') throw _conflict('This transfer is ${t['status']}');
      _cancelTransfer(t, meId, null);
      return {'transfer': _transferDto(t, meId)};
    }
    if (action == 'dispute') {
      if (t['status'] != 'pending') throw _conflict('Only pending transfers can be disputed');
      if (_str(b['reason']).length < 10) throw _bad('reason: At least 10 characters');
      t['status'] = 'disputed';
      _notify(meId, 'transfer.disputed', 'Dispute submitted (demo)',
          'In the full system an admin reviews disputes. This transfer is now frozen.', {'transferId': t['id']});
      return {'transfer': _transferDto(t, meId)};
    }
    throw _notFound('No route');
  }

  /// Both parties confirmed: move ownership, record history, close the sale.
  void _complete(J t, J d) {
    if (d['ownerId'] != t['fromId']) throw _err(409, 'ownership_changed', 'The sender no longer owns this device');
    d['ownerId'] = t['toId'];
    for (final h in _t('history')) {
      if (h['deviceId'] == d['id'] && h['releasedAt'] == null) h['releasedAt'] = _now();
    }
    _t('history').add({
      'id': _id('h_'), 'deviceId': d['id'], 'ownerId': t['toId'], 'acquiredVia': 'transfer',
      'transferId': t['id'], 'acquiredAt': _now(), 'releasedAt': null,
    });
    t['status'] = 'completed';
    t['completedAt'] = _now();
    for (final l in _t('listings')) {
      if (l['deviceId'] == d['id'] && (l['status'] == 'active' || l['status'] == 'reserved')) {
        l['status'] = 'sold';
        for (final r in _t('requests')) {
          if (r['listingId'] == l['id'] && r['status'] == 'pending') r['status'] = 'rejected';
        }
      }
    }
    if (t['purchaseRequestId'] != null) {
      final r = _find('requests', t['purchaseRequestId'] as String);
      if (r != null) r['status'] = 'completed';
    }
    final label = '${d['brand']} ${d['model']}';
    _notify(t['toId'] as String, 'transfer.completed', 'Ownership transferred', 'You are now the registered owner of the $label.',
        {'transferId': t['id'], 'deviceId': d['id']});
    _notify(t['fromId'] as String, 'transfer.completed', 'Transfer complete', 'Ownership of the $label has been transferred.',
        {'transferId': t['id'], 'deviceId': d['id']});
  }

  void _cancelTransfer(J t, String actorId, String? reason) {
    t['status'] = 'cancelled';
    if (t['purchaseRequestId'] != null) {
      final r = _find('requests', t['purchaseRequestId'] as String);
      if (r != null && r['status'] == 'accepted') {
        r['status'] = 'cancelled';
        final l = _find('listings', r['listingId'] as String);
        if (l != null && l['status'] == 'reserved') l['status'] = 'active';
      }
    }
    for (final uid in [t['fromId'], t['toId']]) {
      if (uid == actorId) continue;
      _notify(uid as String, 'transfer.cancelled', 'Transfer cancelled', reason ?? 'An ownership transfer you were part of was cancelled.',
          {'transferId': t['id']});
    }
  }

  // ---------------------------------------------------------------- stolen reports

  dynamic _reports(String method, List<String> seg, J b, String? token) {
    final me = _requireUser(token);
    final meId = me['id'] as String;
    if (method == 'POST' && seg.length == 1) {
      final d = _deviceOr404(_str(b['deviceId']));
      if (d['ownerId'] != meId) throw _forbidden('You do not own this device');
      if (d['registryStatus'] == 'reported_stolen') throw _conflict('This device is already marked as stolen');
      if (_reportPending(d['id'] as String)) throw _conflict('A stolen report for this device is already under review');
      final date = DateTime.tryParse(_str(b['incidentDate']));
      if (date == null) throw _bad('incidentDate: Choose the date');
      if (date.isAfter(DateTime.now())) throw _bad('Incident date cannot be in the future');
      if (_str(b['location']).length < 2) throw _bad('location: Enter the location');
      if (_str(b['description']).length < 10) throw _bad('description: At least 10 characters');
      final r = {
        'id': _id('rep_'), 'deviceId': d['id'], 'reporterId': meId, 'incidentDate': _str(b['incidentDate']),
        'location': _str(b['location']), 'description': _str(b['description']),
        'policeReportNumber': _str(b['policeReportNumber']).isEmpty ? null : _str(b['policeReportNumber']),
        'status': 'pending', 'reviewNote': null, 'reviewedAt': null, 'createdAt': _now(),
      };
      _t('reports').add(r);
      for (final t in _t('transfers').where((t) => t['deviceId'] == d['id'] && t['status'] == 'pending').toList()) {
        _cancelTransfer(t, meId, 'The owner reported this device as stolen.');
      }
      for (final l in _t('listings')) {
        if (l['deviceId'] == d['id'] && (l['status'] == 'active' || l['status'] == 'reserved')) {
          l['status'] = 'withdrawn';
          for (final pr in _t('requests')) {
            if (pr['listingId'] == l['id'] && (pr['status'] == 'pending' || pr['status'] == 'accepted')) pr['status'] = 'rejected';
          }
        }
      }
      return {'report': _reportDto(r)};
    }
    if (method == 'GET' && seg.length == 1) {
      final rows = _t('reports').where((r) => r['reporterId'] == meId).toList()
        ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return {'reports': rows.map(_reportDto).toList()};
    }
    throw _notFound('No route');
  }

  // ---------------------------------------------------------------- documents & notifications

  dynamic _documents(String method, List<UploadFile> files, Map<String, String> fields, String? token) {
    final me = _requireUser(token);
    if (method == 'POST') {
      if (files.isEmpty) throw _bad('No file uploaded');
      final doc = {
        'id': _id('doc_'), 'ownerId': me['id'], 'kind': fields['kind'] ?? 'other', 'path': files.first.path,
        'deviceId': fields['deviceId'], 'stolenReportId': fields['stolenReportId'], 'status': 'pending', 'createdAt': _now(),
      };
      _t('documents').add(doc);
      return {'document': {'id': doc['id'], 'kind': doc['kind'], 'status': doc['status'], 'createdAt': doc['createdAt']}};
    }
    return {
      'documents': _t('documents').where((d) => d['ownerId'] == me['id']).map((d) => {
            'id': d['id'], 'kind': d['kind'], 'status': d['status'], 'deviceId': d['deviceId'],
            'stolenReportId': d['stolenReportId'], 'reviewNote': null, 'createdAt': d['createdAt'],
          }).toList(),
    };
  }

  dynamic _notifications(String method, List<String> seg, Map<String, String> q, String? token) {
    final me = _requireUser(token);
    final mine = _t('notifications').where((n) => n['userId'] == me['id']).toList();
    if (method == 'GET') {
      mine.sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      final unreadOnly = q['unread'] == 'true';
      return {
        'unreadCount': mine.where((n) => n['read'] != true).length,
        'notifications': mine.where((n) => !unreadOnly || n['read'] != true).take(100).toList(),
      };
    }
    if (seg.length == 2 && seg[1] == 'read-all') {
      for (final n in mine) {
        n['read'] = true;
      }
      return null;
    }
    if (seg.length == 3 && seg[2] == 'read') {
      for (final n in mine) {
        if (n['id'] == seg[1]) n['read'] = true;
      }
      return null;
    }
    throw _notFound('No route');
  }

  // ---------------------------------------------------------------- demo-only actions

  dynamic _demoActions(String method, List<String> seg, String? token) {
    final me = _requireUser(token);
    // POST /demo/reports/:id/approve — stands in for the admin dashboard's review step.
    if (method == 'POST' && seg.length == 4 && seg[1] == 'reports' && seg[3] == 'approve') {
      final r = _find('reports', seg[2]) ?? (throw _notFound('Report not found'));
      if (r['reporterId'] != me['id']) throw _forbidden('This is not your report');
      if (r['status'] != 'pending') throw _conflict('This report is already ${r['status']}');
      r['status'] = 'approved';
      r['reviewNote'] = 'Approved by simulated admin review (demo)';
      r['reviewedAt'] = _now();
      final d = _find('devices', r['deviceId'] as String)!;
      d['registryStatus'] = 'reported_stolen';
      _notify(me['id'] as String, 'report.approved', 'Stolen report approved (demo)',
          'Your ${d['brand']} ${d['model']} now shows as "Reported Stolen" in the demo registry.', {'reportId': r['id'], 'deviceId': d['id']});
      return {'report': _reportDto(r)};
    }
    if (method == 'POST' && seg.length == 2 && seg[1] == 'reset') {
      _db = _seed();
      return {'ok': true};
    }
    throw _notFound('No route');
  }
}
