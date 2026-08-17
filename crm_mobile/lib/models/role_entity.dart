import 'package:equatable/equatable.dart';

class RoleDropdownItem extends Equatable {
  final String id;
  final String roleName;
  final String roleCode;

  const RoleDropdownItem({
    required this.id,
    required this.roleName,
    required this.roleCode,
  });

  @override
  List<Object?> get props => [id, roleName, roleCode];
}

class RoleDropdownItemModel extends RoleDropdownItem {
  const RoleDropdownItemModel({
    required super.id,
    required super.roleName,
    required super.roleCode,
  });

  factory RoleDropdownItemModel.fromJson(Map<String, dynamic> json) {
    return RoleDropdownItemModel(
      id: json['id'] ?? '',
      roleName: json['roleName'] ?? '',
      roleCode: json['roleCode'] ?? '',
    );
  }
}

class RolePermission extends Equatable {
  final String module;
  final bool create;
  final bool read;
  final bool update;
  final bool delete;

  const RolePermission({
    required this.module,
    required this.create,
    required this.read,
    required this.update,
    required this.delete,
  });

  @override
  List<Object?> get props => [module, create, read, update, delete];
}

class RolePermissionModel extends RolePermission {
  const RolePermissionModel({
    required super.module,
    required super.create,
    required super.read,
    required super.update,
    required super.delete,
  });

  factory RolePermissionModel.fromJson(Map<String, dynamic> json) {
    return RolePermissionModel(
      module: json['module'] ?? '',
      create: json['create'] ?? false,
      read: json['read'] ?? false,
      update: json['update'] ?? false,
      delete: json['delete'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'module': module,
      'create': create,
      'read': read,
      'update': update,
      'delete': delete,
    };
  }
}

class RoleDetail extends Equatable {
  final String id;
  final String roleCode;
  final String roleName;
  final String description;
  final bool systemRole;
  final List<RolePermission> permissions;

  const RoleDetail({
    required this.id,
    required this.roleCode,
    required this.roleName,
    required this.description,
    required this.systemRole,
    required this.permissions,
  });

  @override
  List<Object?> get props => [id, roleCode, roleName, description, systemRole, permissions];
}

class RoleDetailModel extends RoleDetail {
  const RoleDetailModel({
    required super.id,
    required super.roleCode,
    required super.roleName,
    required super.description,
    required super.systemRole,
    required super.permissions,
  });

  factory RoleDetailModel.fromJson(Map<String, dynamic> json) {
    var rawPermissions = json['permissions'];
    List<RolePermission> perms = [];
    if (rawPermissions is List) {
      perms = rawPermissions.map((p) => RolePermissionModel.fromJson(p)).toList();
    }

    return RoleDetailModel(
      id: json['id'] ?? '',
      roleCode: json['roleCode'] ?? '',
      roleName: json['roleName'] ?? '',
      description: json['description'] ?? '',
      systemRole: json['systemRole'] ?? false,
      permissions: perms,
    );
  }
}
