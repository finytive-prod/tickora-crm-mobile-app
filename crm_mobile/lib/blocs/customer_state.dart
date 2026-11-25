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
  final int totalCount;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String? searchQuery;

  const CustomersLoaded({
    required this.customers,
    this.totalCount = 0,
    this.currentPage = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.searchQuery,
  });

  CustomersLoaded copyWith({
    List<Customer>? customers,
    int? totalCount,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
    String? searchQuery,
  }) {
    return CustomersLoaded(
      customers: customers ?? this.customers,
      totalCount: totalCount ?? this.totalCount,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [customers, totalCount, currentPage, hasMore, isLoadingMore, searchQuery];
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
