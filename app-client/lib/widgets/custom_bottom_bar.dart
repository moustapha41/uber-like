import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Custom Bottom Navigation Bar for motorcycle ride-hailing app
/// Implements thumb-zone optimized navigation with haptic feedback
class CustomBottomBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outline.withAlpha(77), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            HapticFeedback.lightImpact();
            onTap(index);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: colorScheme.primary,
          unselectedItemColor: colorScheme.onSurfaceVariant,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400,
            letterSpacing: -0.1,
          ),
          items: [
            BottomNavigationBarItem(
              icon: _buildIcon(
                icon: Icons.two_wheeler_outlined,
                isSelected: currentIndex == 0,
                context: context,
              ),
              activeIcon: _buildIcon(
                icon: Icons.two_wheeler,
                isSelected: true,
                context: context,
              ),
              label: 'Home',
              tooltip: 'Service selection hub',
            ),
            BottomNavigationBarItem(
              icon: _buildIcon(
                icon: Icons.history_outlined,
                isSelected: currentIndex == 1,
                context: context,
              ),
              activeIcon: _buildIcon(
                icon: Icons.history,
                isSelected: true,
                context: context,
              ),
              label: 'History',
              tooltip: 'Past trips and reordering',
            ),
            BottomNavigationBarItem(
              icon: _buildIcon(
                icon: Icons.person_outline,
                isSelected: currentIndex == 2,
                context: context,
              ),
              activeIcon: _buildIcon(
                icon: Icons.person,
                isSelected: true,
                context: context,
              ),
              label: 'Profile',
              tooltip: 'Account and settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon({
    required IconData icon,
    required bool isSelected,
    required BuildContext context,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary.withAlpha(26)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 24),
    );
  }
}
