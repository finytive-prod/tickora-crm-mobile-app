class Customer {
  final String id;
  final String customerType;
  final String customerName;
  final String companyName;
  final String email;
  final String phone;
  final String designation;
  final String address;
  final String? notes;
  final String? tags;

  Customer({
    required this.id,
    required this.customerType,
    required this.customerName,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.designation,
    required this.address,
    this.notes,
    this.tags,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    String nameVal = (json['customerName'] ?? json['name'] ?? json['fullName'] ?? '').toString().trim();
    if (nameVal.isEmpty) {
      final fName = (json['firstName'] ?? '').toString().trim();
      final lName = (json['lastName'] ?? '').toString().trim();
      nameVal = '$fName $lName'.trim();
    }
    return Customer(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      customerType: (json['customerType'] ?? json['type'] ?? 'INDIVIDUAL').toString(),
      customerName: nameVal.isEmpty ? 'Unnamed' : nameVal,
      companyName: (json['companyName'] ?? json['company'] ?? '').toString(),
      email: _parseEmail(json),
      phone: (json['phone'] ?? json['phoneNumber'] ?? json['mobile'] ?? json['mobileNumber'] ?? '').toString(),
      designation: (json['designation'] ?? json['title'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      notes: json['notes']?.toString(),
      tags: json['tags']?.toString(),
    );
  }

  static String _parseEmail(Map<String, dynamic> json) {
    final candidates = [
      json['email'],
      json['emailId'],
      json['email_id'],
      json['emailAddress'],
      json['email_address'],
      json['mail'],
      json['customerEmail'],
      json['customer_email'],
      json['contactEmail'],
      json['contact_email'],
      json['primaryEmail'],
      json['primary_email'],
      json['officialEmail'],
      json['workEmail'],
      json['userEmail'],
    ];

    for (final candidate in candidates) {
      if (candidate != null) {
        final str = candidate.toString().trim();
        if (str.isNotEmpty && str.toLowerCase() != 'null') {
          return str;
        }
      }
    }

    final nestedObjects = [
      json['contact'],
      json['customer'],
      json['lead'],
      json['details'],
      json['primaryContact'],
      json['contactPerson'],
    ];

    for (final obj in nestedObjects) {
      if (obj is Map<String, dynamic>) {
        final nestedEmail = _parseEmail(obj);
        if (nestedEmail.isNotEmpty) return nestedEmail;
      }
    }

    if (json['emails'] is List && (json['emails'] as List).isNotEmpty) {
      final first = (json['emails'] as List).first;
      if (first is String && first.trim().isNotEmpty && first.trim().toLowerCase() != 'null') {
        return first.trim();
      } else if (first is Map<String, dynamic>) {
        final nested = _parseEmail(first);
        if (nested.isNotEmpty) return nested;
      }
    }

    return '';
  }

  Map<String, dynamic> toJson() {
    return {
      'customerType': customerType,
      'customerName': customerName,
      'companyName': companyName,
      'email': email,
      'phone': phone,
      'designation': designation,
      'address': address,
      'notes': notes,
      'tags': tags,
    };
  }

  String get initials {
    if (customerName.trim().isEmpty) return '?';
    final parts = customerName.trim().split(' ').where((e) => e.trim().isNotEmpty).toList();
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final trimmed = parts.isNotEmpty ? parts[0] : customerName.trim();
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class CustomerListResponse {
  final List<Customer> customers;
  final int totalCount;
  final int totalPages;
  final int currentPage;

  const CustomerListResponse({
    required this.customers,
    required this.totalCount,
    this.totalPages = 1,
    this.currentPage = 0,
  });
}
