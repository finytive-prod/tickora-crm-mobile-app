import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/customer_event.dart';
import 'package:crm_mobile/blocs/customer_state.dart';
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
    on<FetchCustomerTypes>(_onFetchCustomerTypes);
    on<CreateCustomerEvent>(_onCreateCustomer);
    on<UpdateCustomerEvent>(_onUpdateCustomer);
    on<DeleteCustomerEvent>(_onDeleteCustomer);
  }

  Future<void> _onFetchCustomers(FetchCustomers event, Emitter<CustomerState> emit) async {
    emit(CustomerLoading());
    final result = await getCustomersUseCase(searchQuery: event.searchQuery);
    result.fold(
      (failure) => emit(CustomerError(failure.message)),
      (customers) => emit(CustomersLoaded(customers: customers, searchQuery: event.searchQuery)),
    );
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
