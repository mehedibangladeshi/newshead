import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/widgets/brand_mark.dart';

void main() {
  testWidgets('renders the NEWSHEAD wordmark and the chevron badge', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandMark()));
    await tester.pump();

    expect(find.text('NEWSHEAD'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
