import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msg_video_trimmer_example/main.dart';

void main() {
  testWidgets('renders the trimmer UI', (tester) async {
    await tester.pumpWidget(const TrimmerApp());
    expect(find.text('Pick video'), findsOneWidget);
    expect(find.text('Trim'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
