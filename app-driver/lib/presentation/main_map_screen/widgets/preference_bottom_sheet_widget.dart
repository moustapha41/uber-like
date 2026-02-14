import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/app_export.dart';
import '../../../widgets/custom_icon_widget.dart';

class PreferenceBottomSheetWidget extends StatefulWidget {
  const PreferenceBottomSheetWidget({super.key});

  @override
  State<PreferenceBottomSheetWidget> createState() =>
      _PreferenceBottomSheetWidgetState();
}

class _PreferenceBottomSheetWidgetState
    extends State<PreferenceBottomSheetWidget> {
  bool _acceptRides = true;
  bool _acceptDeliveries = true;
  double _radiusKm = 5.0;
  bool _soundNotifications = true;
  bool _vibrationNotifications = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 1.h),
              width: 12.w,
              height: 0.5.h,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(4.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Préférences', style: theme.textTheme.headlineSmall),
                  SizedBox(height: 3.h),
                  Text('Types de courses', style: theme.textTheme.titleMedium),
                  SizedBox(height: 1.h),
                  _buildSwitchTile(
                    title: 'Accepter les courses',
                    subtitle: 'Transport de passagers',
                    value: _acceptRides,
                    onChanged: (value) => setState(() => _acceptRides = value),
                    icon: 'directions_car',
                    theme: theme,
                  ),
                  _buildSwitchTile(
                    title: 'Accepter les livraisons',
                    subtitle: 'Livraison de colis et nourriture',
                    value: _acceptDeliveries,
                    onChanged: (value) =>
                        setState(() => _acceptDeliveries = value),
                    icon: 'local_shipping',
                    theme: theme,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'Rayon de recherche',
                    style: theme.textTheme.titleMedium,
                  ),
                  SizedBox(height: 1.h),
                  Row(
                    children: [
                      CustomIconWidget(
                        iconName: 'my_location',
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                      SizedBox(width: 3.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_radiusKm.toStringAsFixed(1)} km',
                              style: theme.textTheme.titleMedium,
                            ),
                            Slider(
                              value: _radiusKm,
                              min: 1.0,
                              max: 20.0,
                              divisions: 19,
                              label: '${_radiusKm.toStringAsFixed(1)} km',
                              onChanged: (value) =>
                                  setState(() => _radiusKm = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text('Notifications', style: theme.textTheme.titleMedium),
                  SizedBox(height: 1.h),
                  _buildSwitchTile(
                    title: 'Son',
                    subtitle: 'Notification sonore pour nouvelles courses',
                    value: _soundNotifications,
                    onChanged: (value) =>
                        setState(() => _soundNotifications = value),
                    icon: 'volume_up',
                    theme: theme,
                  ),
                  _buildSwitchTile(
                    title: 'Vibration',
                    subtitle: 'Vibration pour nouvelles courses',
                    value: _vibrationNotifications,
                    onChanged: (value) =>
                        setState(() => _vibrationNotifications = value),
                    icon: 'vibration',
                    theme: theme,
                  ),
                  SizedBox(height: 2.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 2.h),
                      ),
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String icon,
    required ThemeData theme,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 1.h),
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(2.w),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomIconWidget(
              iconName: icon,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
