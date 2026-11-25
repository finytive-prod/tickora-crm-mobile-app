import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/customer_event.dart';
import 'package:crm_mobile/blocs/customer_state.dart';
import 'package:crm_mobile/models/customer.dart';
import 'package:crm_mobile/usecases/customer_usecases.dart';

class CustomerBloc extends Bloc<CustomerEvent, CustomerState> {
  final GetCustomersUseCase getCustomersUseCase;
  final GetCustomerTypesUseCase getCustomerTypesUseCase;
  final CreateCustomerUseCase createCustomerUseCase;
  final UpdateCustomerUseCase updateCustomerUseCase;
  final DeleteCustomerUseCase deleteCustomerUseCase;

  CustomerBloc({
    required this.getCustomersUseCase,
    required this.getCustomerTypesUseCase,
    required this.createCustomerUseCase,
    required this.updateCustomerUseCase,
    required this.deleteCustomerUseCase,
  }) : super(CustomerInitial()) {
    on<FetchCustomers>(_onFetchCustomers);
    on<LoadMoreCustomers>(_onLoadMoreCustomers);
    on<FetchCustomerTypes>(_onFetchCustomerTypes);
    on<CreateCustomerEvent>(_onCreateCustomer);
    on<UpdateCustomerEvent>(_onUpdateCustomer);
    on<DeleteCustomerEvent>(_onDeleteCustomer);
  }

  Future<void> _onFetchCustomers(FetchCustomers event, Emitter<CustomerState> emit) async {
    if (!event.isRefresh) {
      emit(CustomerLoading());
    }
    final result = await getCustomersUseCase(page: event.page, size: event.size, searchQuery: event.searchQuery);
    result.fold(
      (failure) => emit(CustomerError(failure.message)),
      (response) {
        // Deduplicate customers by ID
        final customers = response.customers;
        final seen = <String>{};
        final uniqueCustomers = customers.where((c) => seen.add(c.id)).toList();

        final bool isUnpaginated = customers.length > event.size;
        final int total = response.totalCount > uniqueCustomers.length
            ? response.totalCount
            : uniqueCustomers.length;
        final bool hasMore = isUnpaginated
            ? false
            : (response.totalCount > 0 && uniqueCustomers.length >= response.totalCount
                ? false
                : (customers.length >= event.size && customers.isNotEmpty));

        emit(CustomersLoaded(
          customers: uniqueCustomers,
          totalCount: total,
          currentPage: event.page,
          hasMore: hasMore,
          searchQuery: event.searchQuery,
        ));
      },
    );
  }

  Future<void> _onLoadMoreCustomers(LoadMoreCustomers event, Emitter<CustomerState> emit) async {
    final currentState = state;
    if (currentState is CustomersLoaded) {
      if (!currentState.hasMore || currentState.isLoadingMore) {
        return;
      }

      emit(currentState.copyWith(isLoadingMore: true));
      final result = await getCustomersUseCase(page: event.page, size: event.size, searchQuery: event.searchQuery);
      result.fold(
        (failure) => emit(currentState.copyWith(isLoadingMore: false)),
        (response) {
          final newCustomers = response.customers;
          final existingIds = currentState.customers.map((c) => c.id).toSet();
          final uniqueNew = <Customer>[];
          for (final c in newCustomers) {
            if (!existingIds.contains(c.id)) {
              existingIds.add(c.id);
              uniqueNew.add(c);
            }
          }

          if (uniqueNew.isEmpty) {
            emit(currentState.copyWith(hasMore: false, isLoadingMore: false));
            return;
          }

          final updatedList = [...currentState.customers, ...uniqueNew];
          final int total = response.totalCount > updatedList.length
              ? response.totalCount
              : (currentState.totalCount > updatedList.length ? currentState.totalCount : updatedList.length);
          final bool hasMore = (response.totalCount > 0 && updatedList.length >= response.totalCount)
              ? false
              : (newCustomers.length >= event.size);

          emit(currentState.copyWith(
            customers: updatedList,
            totalCount: total,
            currentPage: event.page,
            hasMore: hasMore,
            isLoadingMore: false,
            searchQuery: event.searchQuery,
          ));
        },
      );
    }
  }

  Future<void> _onFetchCustomerTypes(FetchCustomerTypes event, Emitter<CustomerState> emit) async {
    final result = await getCustomerTypesUseCase();
    result.fold(
      (failure) => emit(CustomerError(failure.message)),
      (types) => emit(CustomerTypesLoaded(types: types)),
    );
  }

  Future<void> _onCreateCustomer(CreateCustomerEvent event, Emitter<CustomerState> emit) async {
    emit(CustomerActionLoading());
    final result = await createCustomerUseCase(event.data);
    result.fold(
      (failure) => emit(CustomerError(failure.message)),
      (_) => emit(const CustomerActionSuccess('Customer created successfully')),
    );
  }

  Future<void> _onUpdateCustomer(UpdateCustomerEvent event, Emitter<CustomerState> emit) async {
    emit(CustomerActionLoading());
    final result = await updateCustomerUseCase(event.id, event.data);
    result.fold(
      (failure) => emit(CustomerError(failure.message)),
      (_) => emit(const CustomerActionSuccess('Customer updated successfully')),
    );
  }

  Future<void> _onDeleteCustomer(DeleteCustomerEvent event, Emitter<CustomerState> emit) async {
    emit(CustomerActionLoading());
    final result = await deleteCustomerUseCase(event.id);
    result.fold(
      (failure) => emit(CustomerError(failure.message)),
      (_) => emit(const CustomerActionSuccess('Customer deleted successfully')),
    );
  }
}
