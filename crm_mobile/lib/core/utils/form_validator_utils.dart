import 'package:flutter/material.dart';

/// Validates a form and auto-scrolls to the first invalid field.
/// Returns true if the form is valid, false otherwise.
bool validateAndScrollToError(GlobalKey<FormState> formKey) {
  final isValid = formKey.currentState?.validate() ?? false;
  if (!isValid) {
    // Find the first error field and scroll to it
    final FormState? formState = formKey.currentState;
    if (formState != null) {
      // Use a post-frame callback to ensure the error is rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final errorField = _findFirstErrorField(formKey.currentContext);
        if (errorField != null) {
          Scrollable.ensureVisible(
            errorField,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            alignment: 0.3,
          );
        }
      });
    }
  }
  return isValid;
}

/// Recursively finds the first FormField with an error in the widget tree.
BuildContext? _findFirstErrorField(BuildContext? context) {
  if (context == null) return null;
  BuildContext? errorContext;

  void visitor(Element element) {
    if (errorContext != null) return;

    // Check if this is a FormField with a validation error
    if (element.widget is FormField) {
      final state = (element as StatefulElement).state;
      if (state is FormFieldState && state.hasError) {
        errorContext = element;
        return;
      }
    }
    element.visitChildren(visitor);
  }

  (context as Element).visitChildren(visitor);
  return errorContext;
}
