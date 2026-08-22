import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/customer.dart';

abstract class CustomerState extends Equatable {
  const CustomerState();

  @override
  List<Object?> get props => [];
}

class CustomerInitial extends CustomerState {}

class CustomerLoading extends CustomerState {}

class CustomersLoaded extends CustomerState {
  final List<Customer> customers;
  final String? searchQuery;

  const CustomersLoaded({required this.customers, this.searchQuery});

  @override
  List<Object?> get props => [customers, searchQuery];
}

class CustomerTypesLoaded extends CustomerState {
  final List<String> types;

  const CustomerTypesLoaded({required this.types});

  @override
  List<Object?> get props => [types];
}

class CustomerError extends CustomerState {
  final String message;

  const CustomerError(this.message);

  @override
  List<Object?> get props => [message];
}

class CustomerActionLoading extends CustomerState {}

class CustomerActionSuccess extends CustomerState {
  final String message;

  const CustomerActionSuccess(this.message);

  @override
  List<Object?> get props => [message];
}
