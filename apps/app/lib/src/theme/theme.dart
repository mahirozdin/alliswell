import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// AllisWell brand seed — matches the API's default project color
/// (`#2563EB`, BLUEPRINT §10.2). Kept exported for the palette pickers.
const kSeedColor = Color(0xFF2563EB);

/// Builds the "AllisWell Glass" theme (docs/DESIGN.md). Hand-tuned
/// [ColorScheme] instead of `fromSeed`: every role is contrast-verified
/// (text ≥ 4.5:1, icons/borders ≥ 3:1) — keep it that way when editing.
ThemeData buildAwTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final tokens = isDark ? AwTokens.dark : AwTokens.light;

  final scheme = isDark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF8AB4FF),
          onPrimary: Color(0xFF0A1E4A),
          primaryContainer: Color(0xFF284B8F),
          onPrimaryContainer: Color(0xFFDBE6FF),
          secondary: Color(0xFF9FB2D9),
          onSecondary: Color(0xFF16233F),
          secondaryContainer: Color(0xFF2A3A5E),
          onSecondaryContainer: Color(0xFFDCE5F7),
          tertiary: Color(0xFF2DD4BF),
          onTertiary: Color(0xFF063F38),
          tertiaryContainer: Color(0xFF115E56),
          onTertiaryContainer: Color(0xFFB7F5EA),
          error: Color(0xFFF97066),
          onError: Color(0xFF4A0E0A),
          errorContainer: Color(0xFF7F1D1D),
          onErrorContainer: Color(0xFFFECDCA),
          surface: Color(0xFF131C31),
          onSurface: Color(0xFFE7ECF6),
          surfaceDim: Color(0xFF0B1020),
          surfaceBright: Color(0xFF263252),
          surfaceContainerLowest: Color(0xFF0E1526),
          surfaceContainerLow: Color(0xFF111A2E),
          surfaceContainer: Color(0xFF16203A),
          surfaceContainerHigh: Color(0xFF1C2842),
          surfaceContainerHighest: Color(0xFF233152),
          onSurfaceVariant: Color(0xFFA8B4CE),
          outline: Color(0xFF6A7CA5),
          outlineVariant: Color(0xFF33415F),
          shadow: Color(0xFF000000),
          scrim: Color(0xFF000000),
          inverseSurface: Color(0xFFE7ECF6),
          onInverseSurface: Color(0xFF131C31),
          inversePrimary: Color(0xFF2563EB),
          surfaceTint: Colors.transparent,
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF2563EB),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFDBEAFE),
          onPrimaryContainer: Color(0xFF1E3A8A),
          secondary: Color(0xFF44557E),
          onSecondary: Color(0xFFFFFFFF),
          secondaryContainer: Color(0xFFDDE7F6),
          onSecondaryContainer: Color(0xFF24345C),
          tertiary: Color(0xFF0F766E),
          onTertiary: Color(0xFFFFFFFF),
          tertiaryContainer: Color(0xFFCCFBF1),
          onTertiaryContainer: Color(0xFF134E4A),
          error: Color(0xFFB42318),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFFEE4E2),
          onErrorContainer: Color(0xFF7A271A),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF101828),
          surfaceDim: Color(0xFFE3E9F4),
          surfaceBright: Color(0xFFFFFFFF),
          surfaceContainerLowest: Color(0xFFFFFFFF),
          surfaceContainerLow: Color(0xFFF8FAFD),
          surfaceContainer: Color(0xFFEEF2F9),
          surfaceContainerHigh: Color(0xFFE9EEF7),
          surfaceContainerHighest: Color(0xFFE1E8F3),
          onSurfaceVariant: Color(0xFF43516C),
          outline: Color(0xFF697D9E),
          outlineVariant: Color(0xFFC9D4E5),
          shadow: Color(0xFF0B1020),
          scrim: Color(0xFF0B1020),
          inverseSurface: Color(0xFF1D2739),
          onInverseSurface: Color(0xFFEFF3FA),
          inversePrimary: Color(0xFF8AB4FF),
          surfaceTint: Colors.transparent,
        );

  // Platform system fonts (SF Pro on Apple, Roboto/Segoe elsewhere) with an
  // Apple-like tightening of the display sizes. No network fonts on purpose:
  // the app must feel native and work fully offline.
  final baseText =
      Typography.material2021(
        platform: defaultTargetPlatform,
        colorScheme: scheme,
      ).englishLike.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );
  final textTheme = baseText.copyWith(
    headlineMedium: baseText.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineSmall: baseText.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    titleLarge: baseText.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: baseText.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: baseText.bodyMedium?.copyWith(height: 1.45),
  );

  final hairlineSide = BorderSide(color: tokens.hairline);
  OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[tokens],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    // Screens float on the aurora wash (painted once in app.dart); the veil
    // keeps effective text contrast identical to a solid background.
    scaffoldBackgroundColor: tokens.veil,
    canvasColor: scheme.surface,
    dividerTheme: DividerThemeData(
      color: tokens.hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.l)),
        side: hairlineSide,
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AwRadius.m)),
      ),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      minVerticalPadding: 10,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      hoverColor: scheme.surfaceContainerHighest,
      border: inputBorder(scheme.outline),
      enabledBorder: inputBorder(scheme.outline),
      focusedBorder: inputBorder(scheme.primary, width: 2),
      errorBorder: inputBorder(scheme.error, width: 1.5),
      focusedErrorBorder: inputBorder(scheme.error, width: 2),
      disabledBorder: inputBorder(scheme.outlineVariant),
      hintStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      labelStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: tokens.link),
      helperStyle: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x4,
        vertical: 14,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: AwSpace.x6),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AwRadius.m)),
        ),
        textStyle: textTheme.labelLarge,
        animationDuration: AwMotion.fast,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, 48),
        elevation: 0,
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AwRadius.m)),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: tokens.link,
        side: BorderSide(color: scheme.outline),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AwRadius.m)),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: tokens.link,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AwRadius.s)),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        highlightColor: scheme.primary.withValues(alpha: 0.08),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      highlightElevation: 1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AwRadius.l)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      side: BorderSide(color: scheme.outline, width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? tokens.success
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(
        isDark ? const Color(0xFF06281D) : Colors.white,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outline,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: hairlineSide,
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.secondaryContainer,
      checkmarkColor: scheme.onSecondaryContainer,
      labelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium!.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      useIndicator: true,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: textTheme.labelLarge!.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: textTheme.labelLarge!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: textTheme.titleSmall,
      unselectedLabelStyle: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: tokens.hairline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AwRadius.xl)),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AwRadius.xl)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        side: hairlineSide,
      ),
      textStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AwRadius.m)),
      ),
      insetPadding: const EdgeInsets.all(AwSpace.x4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AwRadius.m)),
          ),
        ),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AwRadius.xl)),
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AwRadius.xl)),
      ),
    ),
    focusColor: scheme.primary.withValues(alpha: 0.12),
    hoverColor: scheme.onSurface.withValues(alpha: 0.04),
    highlightColor: scheme.primary.withValues(alpha: 0.08),
    splashColor: scheme.primary.withValues(alpha: 0.10),
  );
}
