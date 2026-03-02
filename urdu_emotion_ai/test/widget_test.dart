import 'package:flutter_test/flutter_test.dart';
import 'package:urdu_emotion_ai/main.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const UrduEmotionApp());
    expect(find.byType(UrduEmotionApp), findsOneWidget);
  });
}