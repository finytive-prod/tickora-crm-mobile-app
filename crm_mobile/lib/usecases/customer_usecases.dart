import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/customer.dart';
import 'package:crm_mobile/repositories/customer_repository.dart';

class GetCustomersUseCase {
  final CustomerRepository repository;

  GetCustomersUseCase(this.repository);

  Future<Either<Failure, List<Customer>>> call({int page = 0, int size = 20, String? searchQuery}) {
    return repository.getCustomers(page: page, size: size, searchQuery: searchQuery);
  }
}

class GetCustomerTypesUseCase {
  final CustomerRepository repository;

  GetCustomerTypesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() {
    return repository.getCustomerTypes();
  }
}

class CreateCustomerUseCase {
  final CustomerRepository repository;

  CreateCustomerUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> data) {
    return repository.createCustomer(data);
  }
}

class UpdateCustomerUseCase {
  final CustomerRepository repository;

  UpdateCustomerUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, Map<String, dynamic> data) {
    return repository.updateCustomer(id, data);
  }
}

class DeleteCustomerUseCase {
  final CustomerRepository repository;

  DeleteCustomerUseCase(this.repository);

  Future<Either<Failure, void>> call(String id) {
    return repository.deleteCustomer(id);
  }
}
