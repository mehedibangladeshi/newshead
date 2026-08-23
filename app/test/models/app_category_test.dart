import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/app_category.dart';

void main() {
  test('AppCategory instances with the same key and label are equal', () {
    const a = AppCategory(key: 'main', label: 'Main');
    const b = AppCategory(key: 'main', label: 'Main');
    expect(a, equals(b));
  });

  test('AppCategory instances with a different key are not equal', () {
    const a = AppCategory(key: 'main', label: 'Main');
    const b = AppCategory(key: 'politics', label: 'Main');
    expect(a, isNot(equals(b)));
  });
}
