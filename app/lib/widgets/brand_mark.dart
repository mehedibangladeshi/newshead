import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app bar's brand mark: the same red badge + black chevron as the
/// OS app icon (app/assets/icon/icon.png), reproduced as native widgets
/// rather than that flattened PNG — see this feature's plan for why (no
/// real transparency in the export, and the chevron/canvas colors are too
/// close to safely auto-key). "NEWS" in white, "HEAD" in the brand red,
/// both in Anton to match the approved lockup concept.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  static const _accent = Color(0xFFE1483A);
  static const _chevronColor = Color(0xFF121212);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.chevron_right, color: _chevronColor, size: 18),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'NEWS',
                style: GoogleFonts.anton(color: Colors.white, fontSize: 18),
              ),
              TextSpan(
                text: 'HEAD',
                style: GoogleFonts.anton(color: _accent, fontSize: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
