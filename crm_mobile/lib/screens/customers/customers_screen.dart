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
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/widgets/confirmation_dialog.dart';

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
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 250) {
      final bloc = context.read<CustomerBloc>();
      final state = bloc.state;
      if (state is CustomersLoaded && state.hasMore && !state.isLoadingMore) {
        bloc.add(
          LoadMoreCustomers(
            page: state.currentPage + 1,
            searchQuery: state.searchQuery,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<CustomerBloc>().add(FetchCustomers(searchQuery: query));
    });
  }

  void _handleDelete(BuildContext context, Customer customer) {
    ConfirmationDialog.show(
      context,
      title: 'Delete Customer',
      message: 'Are you sure you want to delete ${customer.customerName}?',
      confirmLabel: 'Delete',
      isDestructive: true,
      onConfirm: () {
        context.read<CustomerBloc>().add(DeleteCustomerEvent(customer.id));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CustomerBloc, CustomerState>(
      listener: (context, state) {
        if (state is CustomerActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: const Color(0xFF10B981)));
          context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim(), isRefresh: true));
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
        title: BlocBuilder<CustomerBloc, CustomerState>(
          builder: (context, state) {
            final total = state is CustomersLoaded ? state.totalCount : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Customers',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                if (total != null && total > 0)
                  Text(
                    'Total Customers: $total',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary, size: 22),
            tooltip: 'Refresh Customers',
            onPressed: () {
              context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim(), isRefresh: true));
            },
          ),
          BlocBuilder<CustomerBloc, CustomerState>(
            builder: (context, state) {
              if (state is CustomersLoaded) {
                final count = state.totalCount > 0 ? state.totalCount : state.customers.length;
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count contacts',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
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
                  hintText: 'Search contacts....',
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

                  final bool showLoader = state.isLoadingMore || state.hasMore;
                  final itemCount = customers.length + (showLoader ? 1 : 0);

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim(), isRefresh: true));
                    },
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: itemCount,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index < customers.length) {
                          final customer = customers[index];
                          final priv = sl<PrivilegeService>();
                          final canUpdate = priv.hasPrivilege('CUSTOMER_UPDATE');
                          final canDelete = priv.hasPrivilege('CUSTOMER_DELETE');
                          return CustomerCard(
                            customer: customer,
                            onTap: () {},
                            onEdit: canUpdate
                                ? () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => AddEditCustomerScreen(customer: customer)),
                                    );
                                    if (result == true && context.mounted) {
                                      context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim(), isRefresh: true));
                                    }
                                  }
                                : null,
                            onDelete: canDelete ? () => _handleDelete(context, customer) : null,
                          );
                        }

                        // Bottom loader indicator while fetching remaining customer data
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SpinningLogo(size: 36),
                          ),
                        );
                      },
                    ),
                  );
                }

                if (state is CustomerError) {
                  final err = state.message;
                  if (err.contains('503') || err.toLowerCase().contains('service unavailable')) {
                    return ServerError503Widget(
                      onRetry: () {
                        context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim()));
                      },
                    );
                  }
                  return PoorInternetWidget(
                    title: 'Connection Issue',
                    message: err.isEmpty ? 'Failed to load customers. Please try again.' : err,
                    onRetry: () {
                      context.read<CustomerBloc>().add(FetchCustomers(searchQuery: _searchController.text.trim()));
                    },
                  );
                }
                
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
      floatingActionButton: sl<PrivilegeService>().hasPrivilege('CUSTOMER_CREATE')
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddEditCustomerScreen()),
                );
                if (result == true && context.mounted) {
                  _searchController.clear();
                  context.read<CustomerBloc>().add(const FetchCustomers(isRefresh: true));
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                }
              },
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      )
    );
  }
}

