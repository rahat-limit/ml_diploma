import 'package:flutter/material.dart';
import 'package:ml_practice/models/app_colors.dart';

class ExpandedButton extends StatelessWidget {
  final String text;
  final VoidCallback action;
  final Icon? icon;
  const ExpandedButton(
      {super.key, this.text = 'Continue', required this.action, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: action,
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, SizedBox(width: 5)],
            Text(
              text,
              style: TextStyle(color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}
