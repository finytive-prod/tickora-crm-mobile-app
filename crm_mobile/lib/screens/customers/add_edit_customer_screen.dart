import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/customer.dart';
import 'package:crm_mobile/blocs/customer_bloc.dart';
import 'package:crm_mobile/blocs/customer_event.dart';
import 'package:crm_mobile/blocs/customer_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';
import 'package:crm_mobile/repositories/customer_repository.dart';

class AddEditCustomerScreen extends StatelessWidget {
  final Customer? customer;

  const AddEditCustomerScreen({super.key, this.customer});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerBloc>()..add(FetchCustomerTypes()),
      child: _AddEditCustomerView(customer: customer),
    );
  }
}

class _AddEditCustomerView extends StatefulWidget {
  final Customer? customer;

  const _AddEditCustomerView({this.customer});

  @override
  State<_AddEditCustomerView> createState() => _AddEditCustomerViewState();
}

class _AddEditCustomerViewState extends State<_AddEditCustomerView> {
  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  
  String? _selectedType;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  bool get isEditing => widget.customer != null;

  bool get _isCompanyType {
    if (_selectedType == null) return false;
    final upper = _selectedType!.toUpperCase();
    return upper.contains('COMPANY') || upper.contains('CORPORATE') || upper.contains('BUSINESS') || upper.contains('ENTERPRISE');
  }

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _selectedType = widget.customer!.customerType;
      _nameController.text = widget.customer!.customerName;
      _companyController.text = widget.customer!.companyName;
      _emailController.text = widget.customer!.email;
      _phoneController.text = widget.customer!.phone;
      _addressController.text = widget.customer!.address;
      _notesController.text = widget.customer!.notes ?? '';
      _tagsController.text = widget.customer!.tags ?? '';

      _fetchFreshCustomer();
    }
  }

  Future<void> _fetchFreshCustomer() async {
    try {
      final repo = sl<CustomerRepository>();
      final res = await repo.getCustomerById(widget.customer!.id);
      res.fold((_) {}, (c) {
        if (!mounted) return;
        setState(() {
          if (_emailController.text.trim().isEmpty && c.email.isNotEmpty) {
            _emailController.text = c.email;
          }
          if (_nameController.text.trim().isEmpty && c.customerName.isNotEmpty) {
            _nameController.text = c.customerName;
          }
          if (_phoneController.text.trim().isEmpty && c.phone.isNotEmpty) {
            _phoneController.text = c.phone;
          }
          if (_companyController.text.trim().isEmpty && c.companyName.isNotEmpty) {
            _companyController.text = c.companyName;
          }
          if (_addressController.text.trim().isEmpty && c.address.isNotEmpty) {
            _addressController.text = c.address;
          }
          if (_notesController.text.trim().isEmpty && (c.notes ?? '').isNotEmpty) {
            _notesController.text = c.notes!;
          }
          if (_tagsController.text.trim().isEmpty && (c.tags ?? '').isNotEmpty) {
            _tagsController.text = c.tags!;
          }
          if (_selectedType == null || _selectedType!.isEmpty) {
            _selectedType = c.customerType;
          }
        });
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!validateAndScrollToError(_formKey)) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }

    final data = {
        "customerType": _selectedType ?? "INDIVIDUAL",
        "customerName": _nameController.text.trim(),
        "name": _nameController.text.trim(),
        "companyName": _isCompanyType ? _companyController.text.trim() : "",
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
        "address": _addressController.text.trim(),
        "notes": _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        "tags": _tagsController.text.trim().isEmpty ? null : _tagsController.text.trim(),
      };

      if (isEditing) {
        context.read<CustomerBloc>().add(UpdateCustomerEvent(widget.customer!.id, data));
      } else {
        context.read<CustomerBloc>().add(CreateCustomerEvent(data));
      }
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AppColors.primary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 14),
            validator: required ? (value) => value == null || value.trim().isEmpty ? 'This field is required' : null : null,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderEnabled),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderEnabled),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CustomerBloc, CustomerState>(
      listener: (context, state) {
        if (state is CustomerActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: const Color(0xFF10B981),
          ));
          Navigator.of(context).pop(true);
        } else if (state is CustomerError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppColors.primary,
          ));
        }
      },
      builder: (context, state) {
        bool isLoading = state is CustomerActionLoading || state is CustomerLoading;
        List<String> types = [];
        if (state is CustomerTypesLoaded) {
          types = List<String>.from(state.types);
        }
        if (types.isEmpty) {
          types = ['INDIVIDUAL', 'COMPANY'];
        }
        if (_selectedType != null && !types.contains(_selectedType)) {
          types.insert(0, _selectedType!);
        }
        if (_selectedType == null && types.isNotEmpty) {
          _selectedType = types.first;
        }

        return Scaffold(
          backgroundColor: AppColors.secondary,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              isEditing ? 'Edit Customer' : 'Add Customer',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Type Dropdown
                  const Text(
                    'Customer Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    items: types.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedType = val;
                      });
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.borderEnabled),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.borderEnabled),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildTextField('Customer Name', _nameController, required: true),
                  if (_isCompanyType) _buildTextField('Company Name', _companyController),
                  _buildTextField('Email', _emailController, required: true),
                  _buildTextField('Phone', _phoneController, required: true),
                  _buildTextField('Address', _addressController, maxLines: 2),
                  _buildTextField('Notes', _notesController, maxLines: 3),
                  _buildTextField('Tags', _tagsController),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Add Customer',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
