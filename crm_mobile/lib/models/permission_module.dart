import 'package:equatable/equatable.dart';

class PermissionModule extends Equatable {
  final String module;
  final String displayName;

  const PermissionModule({
    required this.module,
    required this.displayName,
  });

  @override
  List<Object?> get props => [module, displayName];
}

class PermissionModuleModel extends PermissionModule {
  const PermissionModuleModel({
    required super.module,
    required super.displayName,
  });

  factory PermissionModuleModel.fromJson(Map<String, dynamic> json) {
    return PermissionModuleModel(
      module: json['module'] ?? '',
      displayName: json['displayName'] ?? '',
    );
  }
}
