import 'package:equatable/equatable.dart';

abstract class CustomerEvent extends Equatable {
  const CustomerEvent();

  @override
  List<Object?> get props => [];
}

class FetchCustomers extends CustomerEvent {
  final int page;
  final int size;
  final String? searchQuery;
  final bool isRefresh;

  const FetchCustomers({
    this.page = 0,
    this.size = 20,
    this.searchQuery,
    this.isRefresh = false,
  });

  @override
  List<Object?> get props => [page, size, searchQuery, isRefresh];
}

class LoadMoreCustomers extends CustomerEvent {
  final int page;
  final int size;
  final String? searchQuery;

  const LoadMoreCustomers({
    required this.page,
    this.size = 20,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [page, size, searchQuery];
}

class FetchCustomerTypes extends CustomerEvent {}

class CreateCustomerEvent extends CustomerEvent {
  final Map<String, dynamic> data;

  const CreateCustomerEvent(this.data);

  @override
  List<Object?> get props => [data];
}

class UpdateCustomerEvent extends CustomerEvent {
  final String id;
  final Map<String, dynamic> data;

  const UpdateCustomerEvent(this.id, this.data);

  @override
  List<Object?> get props => [id, data];
}

class DeleteCustomerEvent extends CustomerEvent {
  final String id;

  const DeleteCustomerEvent(this.id);

  @override
  List<Object?> get props => [id];
}
