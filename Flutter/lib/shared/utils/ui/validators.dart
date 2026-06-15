import 'package:flutter/widgets.dart';

import 'package:justus/all_imports.dart';

class Validators {
  static String? validateEmail(BuildContext context, String? email) {
    if (email == null || email.trim().isEmpty) {
      return context.loc.auth_validationEmailRequired;
    }
    final emailRegExp = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
    );
    if (!emailRegExp.hasMatch(email.trim())) {
      return context.loc.auth_validationEmailInvalid;
    }

    return null;
  }

  static String? validatePassword(BuildContext context, String? password) {
    if (password == null || password.isEmpty) {
      return context.loc.auth_validationPasswordRequired;
    }
    if (password.length < 8) {
      return context.loc.auth_validationPasswordMinLength;
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return context.loc.auth_validationPasswordLowercase;
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return context.loc.auth_validationPasswordUppercase;
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return context.loc.auth_validationPasswordNumber;
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return context.loc.auth_validationPasswordSymbol;
    }

    return null;
  }

  static String? validateRequired(
    BuildContext context,
    String? value,
    String fieldName,
  ) {
    if (value == null || value.trim().isEmpty) {
      return context.loc.auth_validationRequired(fieldName);
    }

    return null;
  }
}
