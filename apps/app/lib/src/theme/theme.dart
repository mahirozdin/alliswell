import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// AllisWell brand seed — matches the API's default project color
/// (`#2563EB`, BLUEPRINT §10.2). Kept exported for the palette pickers.
const kSeedColor = Color(0xFF2563EB);

/// Builds the "AllisWell Glass v2 — Liquid" theme (docs/DESIGN.md).
/// Hand-tuned [ColorScheme] instead of `fromSeed`: every role is
/// contrast-verified (text ≥ 4.5:1, icons/borders ≥ 3:1) — keep it that way
/// when editing (run `python3 scripts/design/contrast.py`).
///
/// [fontFamilyOverride] exists for the screenshot harness only (the platform
/// default family renders as box glyphs inside `flutter test`); production
/// callers pass nothing and keep the system font (DESIGN §3.3).
ThemeData buildAwTheme(Brightness brightness, {String? fontFamilyOverride}) {
  final isDark = brightness == Brightness.dark;
  final tokens = isDark ? AwTokens.dark : AwTokens.light;

  final scheme = isDark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF3E9BFF),
          onPrimary: Color(0xFF04234E),
          primaryContainer: Color(0xFF1D4FA6),
          onPrimaryContainer: Color(0xFFD9E8FF),
          secondary: Color(0xFFB9AFFF),
          onSecondary: Color(0xFF241B66),
          secondaryContainer: Color(0xFF3B3583),
          onSecondaryContainer: Color(0xFFE6E1FF),
          tertiary: Color(0xFF35D6C2),
          onTertiary: Color(0xFF04352D),
          tertiaryContainer: Color(0xFF0E5B4F),
          onTertiaryContainer: Color(0xFFBDF6EC),
          error: Color(0xFFFF5147),
          onError: Color(0xFF450603),
          errorContainer: Color(0xFF7A1F18),
          onErrorContainer: Color(0xFFFFD9D5),
          surface: Color(0xFF151F3C),
          onSurface: Color(0xFFEAF0FD),
          surfaceDim: Color(0xFF0A0F26),
          surfaceBright: Color(0xFF2A3963),
          surfaceContainerLowest: Color(0xFF0E1630),
          surfaceContainerLow: Color(0xFF121B36),
          surfaceContainer: Color(0xFF182342),
          surfaceContainerHigh: Color(0xFF1F2C51),
          surfaceContainerHighest: Color(0xFF26345E),
          onSurfaceVariant: Color(0xFFAAB6D6),
          outline: Color(0xFF7186B5),
          outlineVariant: Color(0xFF37456B),
          shadow: Color(0xFF000000),
          scrim: Color(0xFF000000),
          inverseSurface: Color(0xFFEAF0FD),
          onInverseSurface: Color(0xFF151F3C),
          inversePrimary: Color(0xFF0A5CFF),
          surfaceTint: Colors.transparent,
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF0A5CFF),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFD6E5FF),
          onPrimaryContainer: Color(0xFF0A3FBF),
          secondary: Color(0xFF5A50E0),
          onSecondary: Color(0xFFFFFFFF),
          secondaryContainer: Color(0xFFE4E1FF),
          onSecondaryContainer: Color(0xFF3A32A8),
          tertiary: Color(0xFF0C7D6C),
          onTertiary: Color(0xFFFFFFFF),
          tertiaryContainer: Color(0xFFBFF2E6),
          onTertiaryContainer: Color(0xFF084F44),
          error: Color(0xFFD70015),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFFFE3E0),
          onErrorContainer: Color(0xFF99000F),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F1B2E),
          surfaceDim: Color(0xFFDEE7F7),
          surfaceBright: Color(0xFFFFFFFF),
          surfaceContainerLowest: Color(0xFFFFFFFF),
          surfaceContainerLow: Color(0xFFF6F9FF),
          surfaceContainer: Color(0xFFEBF1FC),
          surfaceContainerHigh: Color(0xFFE7EEFA),
          surfaceContainerHighest: Color(0xFFDEE8F8),
          onSurfaceVariant: Color(0xFF44536F),
          outline: Color(0xFF63789E),
          outlineVariant: Color(0xFFC7D3E8),
          shadow: Color(0xFF0A1C3D),
          scrim: Color(0xFF0A1C3D),
          inverseSurface: Color(0xFF1D2739),
          onInverseSurface: Color(0xFFEFF3FA),
          inversePrimary: Color(0xFF3E9BFF),
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
        fontFamily: fontFamilyOverride,
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
      letterSpacing: -0.3,
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
    // Liquid Glass control geometry: primary actions are capsules, the way
    // iOS 26 buttons nestle into rounded corners. One prominent (filled)
    // action per screen; everything else stays quieter.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: AwSpace.x6),
        shape: const StadiumBorder(),
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
        shape: const StadiumBorder(),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: tokens.link,
        side: BorderSide(color: scheme.outline),
        shape: const StadiumBorder(),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: tokens.link,
        shape: const StadiumBorder(),
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
      elevation: 4,
      highlightElevation: 2,
      shape: const CircleBorder(),
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
        isDark ? const Color(0xFF052E1B) : Colors.white,
      ),
    ),
    // Switches read as iOS: green when on, white knob.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? (isDark ? scheme.onSurface : scheme.surfaceBright)
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? tokens.success
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
      height: 64,
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
