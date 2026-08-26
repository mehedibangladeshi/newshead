import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/models/filter_option.dart';

void main() {
  test('FilterOption instances with the same key and label are equal', () {
    const a = FilterOption(key: 'bn', label: 'Bangla');
    const b = FilterOption(key: 'bn', label: 'Bangla');
    expect(a, equals(b));
  });

  test('FilterOption instances with a different key are not equal', () {
    const a = FilterOption(key: 'bn', label: 'Bangla');
    const b = FilterOption(key: 'en', label: 'Bangla');
    expect(a, isNot(equals(b)));
  });
}
