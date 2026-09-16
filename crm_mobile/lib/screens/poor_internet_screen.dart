import 'package:flutter/material.dart';
import 'package:crm_mobile/widgets/poor_internet_widget.dart';

class PoorInternetScreen extends StatelessWidget {
  final VoidCallback? onRetry;

  const PoorInternetScreen({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: PoorInternetWidget(
          onRetry: onRetry ?? () => Navigator.maybePop(context),
        ),
      ),
    );
  }
}
