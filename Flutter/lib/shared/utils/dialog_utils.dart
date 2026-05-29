import 'dart:async';

import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class DialogUtils {
  static void showError(BuildContext context, String message, {String? details, String? errorCode}) {
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ErrorDialog(message: message, details: details, errorCode: errorCode),
    ));
  }

  static void showPartnerInvite(BuildContext context) {
    unawaited(PartnerInviteDialog.show(context));
  }
}
