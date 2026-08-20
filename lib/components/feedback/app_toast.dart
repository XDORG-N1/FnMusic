import 'package:flutter/material.dart';

import '../../app/navigator_key.dart';

/// 全局轻提示（SnackBar），无 ScaffoldMessenger 时回退到全局 messenger。
class AppToast {
  AppToast._();

  static void show(BuildContext context, String message) {
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context) ?? appMessengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }
}
