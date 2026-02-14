import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Custom AppBar widget for the ride-hailing driver application.
/// Provides a clean, minimal top navigation optimized for map-focused interface.
/// Designed for occasional two-handed interaction during stationary periods.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Title text displayed in the app bar
  final String title;

  /// Optional leading widget (typically back button or menu icon)
  final Widget? leading;

  /// Optional list of action widgets displayed on the right
  final List<Widget>? actions;

  /// Whether to show the back button automatically
  final bool automaticallyImplyLeading;

  /// Background color override (uses theme color if null)
  final Color? backgroundColor;

  /// Foreground color override (uses theme color if null)
  final Color? foregroundColor;

  /// Elevation override (uses theme elevation if null)
  final double? elevation;

  /// Whether to center the title
  final bool centerTitle;

  /// Optional bottom widget (typically TabBar)
  final PreferredSizeWidget? bottom;

  const CustomAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.centerTitle = false,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: foregroundColor ?? theme.appBarTheme.foregroundColor,
        ),
      ),
      leading: leading,
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: backgroundColor ?? theme.appBarTheme.backgroundColor,
      foregroundColor: foregroundColor ?? theme.appBarTheme.foregroundColor,
      elevation: elevation ?? theme.appBarTheme.elevation,
      centerTitle: centerTitle,
      bottom: bottom,
      iconTheme: IconThemeData(
        color: foregroundColor ?? theme.appBarTheme.foregroundColor,
        size: 24,
      ),
      // Subtle shadow for depth
      shadowColor: isDark
          ? Colors.black.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.1),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}

/// Variant of CustomAppBar with transparent background for overlay on map
class CustomTransparentAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  /// Title text displayed in the app bar
  final String title;

  /// Optional leading widget
  final Widget? leading;

  /// Optional list of action widgets
  final List<Widget>? actions;

  /// Whether to show the back button automatically
  final bool automaticallyImplyLeading;

  /// Text color (defaults to white for visibility on map)
  final Color? textColor;

  const CustomTransparentAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = textColor ?? Colors.white;

    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: effectiveTextColor,
        ),
      ),
      leading: leading,
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      foregroundColor: effectiveTextColor,
      elevation: 0,
      iconTheme: IconThemeData(color: effectiveTextColor, size: 24),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Variant of CustomAppBar with search functionality
class CustomSearchAppBar extends StatefulWidget implements PreferredSizeWidget {
  /// Hint text for search field
  final String searchHint;

  /// Callback when search text changes
  final ValueChanged<String>? onSearchChanged;

  /// Callback when search is submitted
  final ValueChanged<String>? onSearchSubmitted;

  /// Optional leading widget
  final Widget? leading;

  /// Optional list of action widgets
  final List<Widget>? actions;

  /// Initial search text
  final String? initialSearchText;

  const CustomSearchAppBar({
    super.key,
    this.searchHint = 'Search location...',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.leading,
    this.actions,
    this.initialSearchText,
  });

  @override
  State<CustomSearchAppBar> createState() => _CustomSearchAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _CustomSearchAppBarState extends State<CustomSearchAppBar> {
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialSearchText);
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      leading: widget.leading,
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: theme.appBarTheme.foregroundColor,
        ),
        decoration: InputDecoration(
          hintText: widget.searchHint,
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: theme.appBarTheme.foregroundColor?.withValues(alpha: 0.6),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    widget.onSearchChanged?.call('');
                  },
                  color: theme.appBarTheme.foregroundColor,
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {}); // Rebuild to show/hide clear button
          widget.onSearchChanged?.call(value);
        },
        onSubmitted: widget.onSearchSubmitted,
      ),
      actions: widget.actions,
      backgroundColor: theme.appBarTheme.backgroundColor,
      foregroundColor: theme.appBarTheme.foregroundColor,
      elevation: theme.appBarTheme.elevation,
    );
  }
}
