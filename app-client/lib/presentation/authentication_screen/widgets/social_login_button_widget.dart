import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

/// Social login button widget for third-party authentication
/// Provides consistent styling for Google, Apple, and Facebook login options
class SocialLoginButtonWidget extends StatelessWidget {
  final String provider;
  final String iconName;
  final VoidCallback onTap;

  const SocialLoginButtonWidget({
    super.key,
    required this.provider,
    required this.iconName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 1.8.h),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomIconWidget(
            iconName: iconName,
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
          SizedBox(width: 3.w),
          Text(
            provider,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
