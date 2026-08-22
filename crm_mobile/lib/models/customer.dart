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
    return Customer(
      id: json['id'] ?? '',
      customerType: json['customerType'] ?? 'INDIVIDUAL',
      customerName: json['customerName'] ?? '',
      companyName: json['companyName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      designation: json['designation'] ?? '',
      address: json['address'] ?? '',
      notes: json['notes'],
      tags: json['tags'],
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
    if (customerName.isEmpty) return '?';
    final parts = customerName.split(' ');
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return customerName.substring(0, customerName.length >= 2 ? 2 : 1).toUpperCase();
  }
}
