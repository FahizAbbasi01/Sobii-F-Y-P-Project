// Typed views over API JSON. Only fields the app uses are mapped.

num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
String? _str(dynamic v) => v?.toString();

class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? city;
  final String role;
  final String? createdAt;

  AppUser({required this.id, required this.email, required this.fullName, this.phone, this.city, required this.role, this.createdAt});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        email: j['email'] as String,
        fullName: j['fullName'] as String,
        phone: _str(j['phone']),
        city: _str(j['city']),
        role: (j['role'] ?? 'user') as String,
        createdAt: _str(j['createdAt']),
      );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }
}

class ImeiEntry {
  final String imei;
  final int slot;
  ImeiEntry(this.imei, this.slot);
  factory ImeiEntry.fromJson(Map<String, dynamic> j) => ImeiEntry(j['imei'] as String, (j['slot'] as num).toInt());
}

class Device {
  final String id;
  final String brand;
  final String model;
  final int? storageGb;
  final String? color;
  final String registryStatus; // registered | reported_stolen
  final List<ImeiEntry> imeis;
  final Map<String, dynamic>? liveListing;
  final String? pendingTransferId;
  final bool reportPending;
  final String? registeredAt;

  Device({
    required this.id,
    required this.brand,
    required this.model,
    this.storageGb,
    this.color,
    required this.registryStatus,
    required this.imeis,
    this.liveListing,
    this.pendingTransferId,
    this.reportPending = false,
    this.registeredAt,
  });

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'] as String,
        brand: j['brand'] as String,
        model: j['model'] as String,
        storageGb: _num(j['storageGb'])?.toInt(),
        color: _str(j['color']),
        registryStatus: (j['registryStatus'] ?? 'registered') as String,
        imeis: ((j['imeis'] as List?) ?? []).map((e) => ImeiEntry.fromJson(e as Map<String, dynamic>)).toList(),
        liveListing: j['liveListing'] as Map<String, dynamic>?,
        pendingTransferId: _str(j['pendingTransferId']),
        reportPending: j['reportPending'] == true,
        registeredAt: _str(j['registeredAt']),
      );

  String get name => '$brand $model';
  String get subtitle => [if (storageGb != null) '${storageGb}GB', if (color != null && color!.isNotEmpty) color].join(' • ');
  bool get isStolen => registryStatus == 'reported_stolen';
  bool get isBusy => liveListing != null || pendingTransferId != null || reportPending;
  String? get primaryImei => imeis.isEmpty ? null : imeis.first.imei;
}

class OwnershipRecord {
  final String ownerName;
  final bool isYou;
  final String acquiredVia;
  final String? acquiredAt;
  final String? releasedAt;
  OwnershipRecord({required this.ownerName, required this.isYou, required this.acquiredVia, this.acquiredAt, this.releasedAt});
  factory OwnershipRecord.fromJson(Map<String, dynamic> j) => OwnershipRecord(
        ownerName: (j['ownerName'] ?? '') as String,
        isYou: j['isYou'] == true,
        acquiredVia: (j['acquiredVia'] ?? '') as String,
        acquiredAt: _str(j['acquiredAt']),
        releasedAt: _str(j['releasedAt']),
      );
}

class ListingImage {
  final String id;
  final String? url;
  ListingImage(this.id, this.url);
}

class Listing {
  final String id;
  final String title;
  final String? description;
  final num price;
  final String condition;
  final String city;
  final String status;
  final String? createdAt;
  final List<ListingImage> images;
  final String deviceId;
  final String brand;
  final String model;
  final int? storageGb;
  final String? color;
  final String registryStatus;
  final String? imeiLast4;
  final int ownerCount;
  final String sellerId;
  final String sellerName;
  final String? sellerCity;
  final String? sellerSince;
  final int sellerSoldCount;
  final int pendingRequests;

  Listing({
    required this.id,
    required this.title,
    this.description,
    required this.price,
    required this.condition,
    required this.city,
    required this.status,
    this.createdAt,
    required this.images,
    required this.deviceId,
    required this.brand,
    required this.model,
    this.storageGb,
    this.color,
    required this.registryStatus,
    this.imeiLast4,
    this.ownerCount = 1,
    required this.sellerId,
    required this.sellerName,
    this.sellerCity,
    this.sellerSince,
    this.sellerSoldCount = 0,
    this.pendingRequests = 0,
  });

  factory Listing.fromJson(Map<String, dynamic> j) {
    final d = (j['device'] ?? {}) as Map<String, dynamic>;
    final s = (j['seller'] ?? {}) as Map<String, dynamic>;
    return Listing(
      id: j['id'] as String,
      title: j['title'] as String,
      description: _str(j['description']),
      price: _num(j['price']) ?? 0,
      condition: (j['condition'] ?? '') as String,
      city: (j['city'] ?? '') as String,
      status: (j['status'] ?? 'active') as String,
      createdAt: _str(j['createdAt']),
      images: ((j['images'] as List?) ?? [])
          .map((e) => ListingImage((e as Map)['id'] as String, _str(e['url'])))
          .toList(),
      deviceId: (d['id'] ?? '') as String,
      brand: (d['brand'] ?? '') as String,
      model: (d['model'] ?? '') as String,
      storageGb: _num(d['storageGb'])?.toInt(),
      color: _str(d['color']),
      registryStatus: (d['registryStatus'] ?? 'registered') as String,
      imeiLast4: _str(d['imeiLast4']),
      ownerCount: _num(d['ownerCount'])?.toInt() ?? 1,
      sellerId: (s['id'] ?? '') as String,
      sellerName: (s['name'] ?? '') as String,
      sellerCity: _str(s['city']),
      sellerSince: _str(s['memberSince']),
      sellerSoldCount: _num(s['soldCount'])?.toInt() ?? 0,
      pendingRequests: _num(j['pendingRequests'])?.toInt() ?? 0,
    );
  }

  String? get coverUrl => images.isEmpty ? null : images.first.url;
  String get specLine => [if (storageGb != null) '${storageGb}GB', if (color != null && color!.isNotEmpty) color].join(' • ');
}

class PurchaseRequest {
  final String id;
  final String status;
  final num offerPrice;
  final String? message;
  final String? createdAt;
  final String role; // buyer | seller
  final String listingId;
  final String listingTitle;
  final num listingPrice;
  final String listingStatus;
  final String deviceName;
  final String buyerName;
  final String? buyerCity;
  final String sellerName;
  final String? transferId;
  final String? transferStatus;

  PurchaseRequest({
    required this.id,
    required this.status,
    required this.offerPrice,
    this.message,
    this.createdAt,
    required this.role,
    required this.listingId,
    required this.listingTitle,
    required this.listingPrice,
    required this.listingStatus,
    required this.deviceName,
    required this.buyerName,
    this.buyerCity,
    required this.sellerName,
    this.transferId,
    this.transferStatus,
  });

  factory PurchaseRequest.fromJson(Map<String, dynamic> j) {
    final l = j['listing'] as Map<String, dynamic>;
    final d = j['device'] as Map<String, dynamic>;
    final b = j['buyer'] as Map<String, dynamic>;
    final s = j['seller'] as Map<String, dynamic>;
    final t = j['transfer'] as Map<String, dynamic>?;
    return PurchaseRequest(
      id: j['id'] as String,
      status: j['status'] as String,
      offerPrice: _num(j['offerPrice']) ?? 0,
      message: _str(j['message']),
      createdAt: _str(j['createdAt']),
      role: j['role'] as String,
      listingId: l['id'] as String,
      listingTitle: l['title'] as String,
      listingPrice: _num(l['price']) ?? 0,
      listingStatus: l['status'] as String,
      deviceName: '${d['brand']} ${d['model']}',
      buyerName: (b['name'] ?? '') as String,
      buyerCity: _str(b['city']),
      sellerName: (s['name'] ?? '') as String,
      transferId: _str(t?['id']),
      transferStatus: _str(t?['status']),
    );
  }
}

class Transfer {
  final String id;
  final String status;
  final String role; // sender | recipient
  final String deviceId;
  final String deviceName;
  final String? imeiLast4;
  final String fromName;
  final String toName;
  final String? toEmail;
  final String? purchaseRequestId;
  final String? senderConfirmedAt;
  final String? recipientConfirmedAt;
  final bool youConfirmed;
  final String? createdAt;
  final String? completedAt;

  Transfer({
    required this.id,
    required this.status,
    required this.role,
    required this.deviceId,
    required this.deviceName,
    this.imeiLast4,
    required this.fromName,
    required this.toName,
    this.toEmail,
    this.purchaseRequestId,
    this.senderConfirmedAt,
    this.recipientConfirmedAt,
    required this.youConfirmed,
    this.createdAt,
    this.completedAt,
  });

  factory Transfer.fromJson(Map<String, dynamic> j) {
    final d = j['device'] as Map<String, dynamic>;
    final f = j['from'] as Map<String, dynamic>;
    final t = j['to'] as Map<String, dynamic>;
    return Transfer(
      id: j['id'] as String,
      status: j['status'] as String,
      role: j['role'] as String,
      deviceId: d['id'] as String,
      deviceName: '${d['brand']} ${d['model']}',
      imeiLast4: _str(d['imeiLast4']),
      fromName: (f['name'] ?? '') as String,
      toName: (t['name'] ?? '') as String,
      toEmail: _str(t['email']),
      purchaseRequestId: _str(j['purchaseRequestId']),
      senderConfirmedAt: _str(j['senderConfirmedAt']),
      recipientConfirmedAt: _str(j['recipientConfirmedAt']),
      youConfirmed: j['youConfirmed'] == true,
      createdAt: _str(j['createdAt']),
      completedAt: _str(j['completedAt']),
    );
  }

  bool get isSender => role == 'sender';
}

class StolenReport {
  final String id;
  final String deviceName;
  final String? incidentDate;
  final String location;
  final String status;
  final String? reviewNote;
  final String? createdAt;

  StolenReport({required this.id, required this.deviceName, this.incidentDate, required this.location, required this.status, this.reviewNote, this.createdAt});

  factory StolenReport.fromJson(Map<String, dynamic> j) {
    final d = j['device'] as Map<String, dynamic>?;
    return StolenReport(
      id: j['id'] as String,
      deviceName: d == null ? 'Device' : '${d['brand']} ${d['model']}',
      incidentDate: _str(j['incidentDate']),
      location: (j['location'] ?? '') as String,
      status: j['status'] as String,
      reviewNote: _str(j['reviewNote']),
      createdAt: _str(j['createdAt']),
    );
  }
}

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final String? createdAt;

  AppNotification({required this.id, required this.type, required this.title, required this.body, required this.data, required this.read, this.createdAt});

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? {},
        read: j['read'] == true,
        createdAt: _str(j['createdAt']),
      );
}

class RegistryResult {
  final String imei;
  final String status; // invalid | not_found | registered | reported_stolen
  final String? reason;
  final String disclaimer;
  final String? checkedAt;
  final Map<String, dynamic>? device;

  RegistryResult({required this.imei, required this.status, this.reason, required this.disclaimer, this.checkedAt, this.device});

  factory RegistryResult.fromJson(Map<String, dynamic> j) => RegistryResult(
        imei: j['imei'] as String,
        status: j['status'] as String,
        reason: _str(j['reason']),
        disclaimer: (j['disclaimer'] ?? '') as String,
        checkedAt: _str(j['checkedAt']),
        device: j['device'] as Map<String, dynamic>?,
      );
}
