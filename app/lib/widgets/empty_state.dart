import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  final bool hasActiveFilters;

  const EmptyState({super.key, this.hasActiveFilters = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hasActiveFilters ? 'No stories match your filters' : 'No stories yet',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
