import 'package:flutter_test/flutter_test.dart';
import 'package:tracking_system_app/main.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const TrackingSystemApp());
    expect(find.byType(TrackingSystemApp), findsOneWidget);
  });
}
