import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/customer.dart';
import 'package:crm_mobile/widgets/customer_card.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/blocs/customer_bloc.dart';
import 'package:crm_mobile/blocs/customer_event.dart';
import 'package:crm_mobile/blocs/customer_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/empty_state_widget.dart';
import 'package:crm_mobile/widgets/poor_internet_widget.dart';
import 'package:crm_mobile/widgets/server_error_503_widget.dart';
import 'package:crm_mobile/screens/customers/add_edit_customer_screen.dart';
import 'package:crm_mobile/core/utils/text_selection_utils.dart';

class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerBloc>()..add(const FetchCustomers()),
      child: const _CustomersView(),
    );
  }
}

class _CustomersView extends StatefulWidget {
  const _CustomersView();

  @override
  State<_CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<_CustomersView> {
  final TextEditingController _searchController = TextEditingController();
  
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<CustomerBloc>().add(FetchCustomers(searchQuery: query));
    });
  }

  void _handleDelete(BuildContext context, Customer customer) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Are you sure you want to delete ${customer.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<CustomerBloc>().add(DeleteCustomerEvent(customer.id));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CustomerBloc, CustomerState>(
      listener: (context, state) {
        if (state is CustomerActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: const Color(0xFF10B981)));
          context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text));
        } else if (state is CustomerError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: AppColors.primary));
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Customers',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary, size: 22),
            tooltip: 'Refresh Customers',
            onPressed: () {
              context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim()));
            },
          ),
          BlocBuilder<CustomerBloc, CustomerState>(
            builder: (context, state) {
              if (state is CustomersLoaded) {
                return Text(
                  '${state.customers.length} contacts',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                );
              }
              return const SizedBox();
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderEnabled),
              ),
              child: TextField(
                controller: _searchController,
                enableInteractiveSelection: true,
                selectionControls: MaterialTextSelectionControls(),
                contextMenuBuilder: buildAdaptiveContextMenu,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: AppColors.textHint),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          
          // Customer List
          Expanded(
            child: BlocBuilder<CustomerBloc, CustomerState>(
              builder: (context, state) {
                if (state is CustomerLoading || state is CustomerInitial) {
                  return const Center(child: SpinningLogo(size: 60));
                }
                
                if (state is CustomersLoaded) {
                  final customers = state.customers;
                  if (customers.isEmpty) {
                    return EmptyStateWidget(
                      title: 'No Customers Found',
                      message: _searchController.text.isEmpty
                          ? 'You haven\'t added any customer contacts yet.'
                          : 'No customers match your search "${_searchController.text}".',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return CustomerCard(
                        customer: customer,
                        onTap: () {},
                        onEdit: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AddEditCustomerScreen(customer: customer)),
                          );
                          if (result == true && context.mounted) {
                            context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text));
                          }
                        },
                        onDelete: () => _handleDelete(context, customer),
                      );
                    },
                  );
                }

                if (state is CustomerError) {
                  final err = state.message;
                  if (err.contains('503') || err.toLowerCase().contains('service unavailable')) {
                    return ServerError503Widget(
                      onRetry: () {
                        context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text));
                      },
                    );
                  }
                  return PoorInternetWidget(
                    title: 'Connection Issue',
                    message: err.isEmpty ? 'Failed to load customers. Please try again.' : err,
                    onRetry: () {
                      context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text));
                    },
                  );
                }
                
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEditCustomerScreen()),
          );
          if (result == true && context.mounted) {
            context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text));
          }
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      )
    );
  }
}

