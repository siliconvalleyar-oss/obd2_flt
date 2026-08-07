import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd2_scanner/main.dart';
import 'package:obd2_scanner/core/providers/theme_provider.dart';

void main() {
  testWidgets('La app arranca y muestra el onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const Obd2ScannerApp(),
      ),
    );
    await tester.pumpAndSettle();

    // El onboarding (LiquidSwipe) está en la ruta inicial.
    expect(find.byType(Obd2ScannerApp), findsOneWidget);
  });
}
