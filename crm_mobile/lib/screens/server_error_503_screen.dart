import 'package:flutter/material.dart';
import 'package:crm_mobile/widgets/server_error_503_widget.dart';

class ServerError503Screen extends StatelessWidget {
  final VoidCallback? onRetry;

  const ServerError503Screen({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ServerError503Widget(
          onRetry: onRetry ?? () => Navigator.maybePop(context),
        ),
      ),
    );
  }
}
