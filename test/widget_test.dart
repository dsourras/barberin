import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barbero/main.dart';

void main() {
  testWidgets('renders auth landing screen', (tester) async {
    await tester.pumpWidget(const BarberoApp());

    expect(find.text('Σύνδεση'), findsOneWidget);
    expect(find.text('Εγγραφή'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3));
  });
}
