import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app bar's brand mark: the same red badge + black chevron as the
/// OS app icon (app/assets/icon/icon.png), reproduced as native widgets
/// rather than that flattened PNG — see this feature's plan for why (no
/// real transparency in the export, and the chevron/canvas colors are too
/// close to safely auto-key). "NEWS" in white, "HEAD" in the brand red,
/// both in Anton to match the approved lockup concept.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    final typography =
        Theme.of(context).extension<AppTypography>() ?? AppTypography.standard();
    final wordmark = typography.wordmark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.chevron_right,
            color: AppColors.background,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'NEWS',
                style: wordmark.copyWith(color: Colors.white),
              ),
              TextSpan(
                text: 'HEAD',
                style: wordmark.copyWith(color: AppColors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
