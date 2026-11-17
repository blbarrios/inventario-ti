import 'package:flutter/material.dart';

// Direction: a quiet network closet. Graphite ink on white label stock,
// cool rack-metal grays, and colour reserved for status LEDs. Structure is
// drawn with hairlines only (no shadows); the one "brand" colour is ink.

// Surfaces, from the page up.
const canvas = Color(0xFFF5F6F8); // page
const sheet = Color(0xFFFFFFFF); // panels, markers, label stock
const well = Color(0xFFF0F1F4); // inset: inputs, thumbnails, code tags
const planPaper = Color(0xFFFAFBFC); // floor-plan sheet

// Ink, four levels.
const ink = Color(0xFF14161B); // primary text, primary action
const inkSoft = Color(0xFF4B505C); // secondary text
const inkFaint = Color(0xFF6C7180); // metadata (4.9:1 on white)
const inkGhost = Color(0xFFA3A8B4); // disabled, decorative only

// Lines.
const hairline = Color(0xFFE3E5EA);
const hairlineStrong = Color(0xFFCDD1D9);
const selectedFill = Color(0xFFEDEEF2);

const sans = 'Plex';
const mono = 'PlexMono';

const radiusControl = 8.0;
const radiusSheet = 12.0;

TextStyle monoStyle(
        {double size = 12.5,
        FontWeight weight = FontWeight.w500,
        Color color = ink}) =>
    TextStyle(
      fontFamily: mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData inventoryTheme() {
  const scheme = ColorScheme.light(
    primary: ink,
    onPrimary: sheet,
    secondary: inkSoft,
    onSecondary: sheet,
    surface: sheet,
    onSurface: ink,
    onSurfaceVariant: inkSoft,
    surfaceContainerLowest: sheet,
    surfaceContainerLow: canvas,
    surfaceContainer: well,
    surfaceContainerHigh: well,
    surfaceContainerHighest: well,
    outline: hairlineStrong,
    outlineVariant: hairline,
    error: Color(0xFFB4232A),
  );

  // Ratio ~1.2 from a 14px body; weight and ink level carry most hierarchy.
  const text = TextTheme(
    headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6),
    headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -.4),
    titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2),
    titleMedium: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -.1),
    titleSmall:
        TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 15, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: inkFaint),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  );

  final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl));
  const controlText =
      TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w500);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: sans,
    scaffoldBackgroundColor: canvas,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .merge(text)
        .apply(bodyColor: ink, displayColor: ink, fontFamily: sans),
    splashFactory: InkRipple.splashFactory,
    hoverColor: const Color(0x0A14161B),
    focusColor: const Color(0x1F14161B),
    highlightColor: Colors.transparent,
    dividerTheme:
        const DividerThemeData(color: hairline, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: inkSoft, size: 20),
    appBarTheme: const AppBarTheme(
      backgroundColor: sheet,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleSpacing: 4,
      shape: Border(bottom: BorderSide(color: hairline)),
      titleTextStyle: TextStyle(
          fontFamily: sans,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
          letterSpacing: -.1),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      backgroundColor: ink,
      foregroundColor: sheet,
      disabledBackgroundColor: well,
      disabledForegroundColor: inkGhost,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: controlText,
      shape: controlShape,
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      backgroundColor: sheet,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      side: const BorderSide(color: hairlineStrong),
      textStyle: controlText,
      shape: controlShape,
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(0, 44),
      textStyle: controlText,
      shape: controlShape,
    )),
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
      foregroundColor: inkSoft,
      shape: controlShape,
    )),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.standard,
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        textStyle: const WidgetStatePropertyAll(controlText),
        backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? ink : sheet),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? sheet : inkSoft),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? sheet : inkSoft),
        side: const WidgetStatePropertyAll(BorderSide(color: hairlineStrong)),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: well,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: inkFaint, fontSize: 14),
      labelStyle: const TextStyle(color: inkFaint, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: inkSoft),
      prefixIconColor: inkFaint,
      suffixIconColor: inkFaint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: const BorderSide(color: ink, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle:
          const TextStyle(fontFamily: sans, fontSize: 14, color: sheet),
      shape: controlShape,
      width: 420,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
          fontFamily: sans,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: ink),
      contentTextStyle: const TextStyle(
          fontFamily: sans, fontSize: 14, height: 1.45, color: inkSoft),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: sheet,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: hairlineStrong,
      dragHandleSize: Size(36, 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration:
          BoxDecoration(color: ink, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontFamily: sans, fontSize: 12, color: sheet),
      waitDuration: const Duration(milliseconds: 400),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: ink,
      selectionColor: Color(0x3314161B),
      selectionHandleColor: ink,
    ),
  );
}

/// A panel: white label stock with a hairline edge. No shadow.
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSheet),
          side: const BorderSide(color: hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// A quiet "add" affordance: a plus in an inset square, then a label.
class AddRow extends StatelessWidget {
  const AddRow({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: well,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.add_rounded, size: 18, color: inkSoft),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: ink)),
          ]),
        ),
      );
}

/// Asset code printed like a labeller tape: mono on an inset strip.
class CodeTag extends StatelessWidget {
  const CodeTag(this.code, {super.key, this.small = false});
  final String code;
  final bool small;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: well,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: small ? 5 : 6, vertical: small ? 1 : 2),
          child: Text(code,
              style: monoStyle(size: small ? 11.5 : 12.5, color: inkSoft)),
        ),
      );
}
