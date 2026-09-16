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
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? json['phoneNumber'] ?? json['mobile'] ?? '').toString(),
      designation: (json['designation'] ?? json['title'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      notes: json['notes']?.toString(),
      tags: json['tags']?.toString(),
    );
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
