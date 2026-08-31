import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medstock/main.dart';
import 'package:medstock/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:medstock/components/dose_editor.dart';
import 'package:medstock/helpers/date_helpers.dart';
import 'package:medstock/models/dose_assignment.dart';
import 'package:medstock/models/medicine.dart';
import 'package:medstock/providers/app_provider.dart';

/// A one-patient, one-a-day medicine with the given starting stock.
Medicine _medicine(String name, String strength, double stock, int patientId) {
  final now = DateTime.now();
  return Medicine(
    name: name,
    strength: strength,
    stockQty: stock,
    stockAsOf: Dates.today(),
    createdAt: now,
    updatedAt: now,
    assignments: [
      DoseAssignment(patientId: patientId, startDate: Dates.today()),
    ],
  );
}

/// Drives the real app on a real device: real sqflite, real plugins, real
/// rendering. Everything here goes through the UI the way a person would.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Wipes the on-device database so each run starts from a clean book.
  Future<void> resetDatabase() async {
    await DatabaseService.instance.clearAll();
  }

  Future<void> boot(WidgetTester tester) async {
    await resetDatabase();
    await tester.pumpWidget(const MedstockApp());
    // Splash loads the database, then replaces itself with the shell.
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Scrolls [finder] into view, then interacts. Flutter does not scroll for
  /// you: enterText and tap against an off-screen widget fail silently, which
  /// is exactly how this test first passed while doing nothing.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(TextFormField, label);
    await reveal(tester, field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps the app-bar "manage patients" icon and adds one patient.
  Future<void> addPatient(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();

    // FAB on the patients screen, or the empty-state button.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Patient').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), name);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Back to the dashboard.
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  group('Medstock on device', () {
    testWidgets('cold start shows the empty stock book', (tester) async {
      await boot(tester);

      expect(find.text('Medstock'), findsOneWidget);
      expect(find.text('Your stock book is empty'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
    });

    testWidgets('adding patients grows the dashboard tab row', (tester) async {
      await boot(tester);

      await addPatient(tester, 'Mom');
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Mom'), findsWidgets);

      await addPatient(tester, 'Dad');
      expect(find.text('Dad'), findsWidgets);
    });

    testWidgets('shared medicine: per-patient dosage sums on the All tab',
        (tester) async {
      await boot(tester);
      await addPatient(tester, 'Mom');
      await addPatient(tester, 'Dad');

      // --- add the medicine through the real form ---
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Medicine'));
      await tester.pumpAndSettle();

      await fill(tester, 'Medicine name', 'Dytor');
      await fill(tester, 'Strength (optional)', '5');
      await fill(tester, 'In stock now', '60');

      // Attach Mom at the default 1 a day.
      final momEditor = find.ancestor(
        of: find.text('Mom'),
        matching: find.byType(DoseEditor),
      );
      await tapVisible(
        tester,
        find.descendant(of: momEditor, matching: find.byType(Switch)),
      );

      // Attach Dad, then raise him to twice a day.
      final dadEditor = find.ancestor(
        of: find.text('Dad'),
        matching: find.byType(DoseEditor),
      );
      await tapVisible(
        tester,
        find.descendant(of: dadEditor, matching: find.byType(Switch)),
      );

      final dadTimesADay = find
          .ancestor(
            of: find.descendant(
              of: dadEditor,
              matching: find.text('Times a day'),
            ),
            matching: find.byType(StepperField),
          )
          .first;
      await tapVisible(
        tester,
        find.descendant(
          of: dadTimesADay,
          matching: find.widgetWithIcon(IconButton, Icons.add),
        ),
      );

      // Mom 1 + Dad 2 = 3 a day for the household.
      await reveal(tester, find.text('PATIENTS & DOSAGE'));
      expect(find.textContaining('Total 3 tablets / day'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // --- All tab shows the household total ---
      expect(find.text('Dytor 5'), findsOneWidget);
      expect(find.text('3 tablets / day'), findsOneWidget);
      expect(find.textContaining('60 tablets in stock'), findsOneWidget);

      // --- Dad's tab shows only his own 2/day ---
      await tester.tap(find.text('Dad').last);
      await tester.pumpAndSettle();
      expect(find.text('2 tablets / day'), findsOneWidget);

      // --- Mom's tab shows 1/day ---
      await tester.tap(find.text('Mom').last);
      await tester.pumpAndSettle();
      expect(find.text('1 tablet / day'), findsOneWidget);
    });

    testWidgets('search filters, then an order is generated and formatted',
        (tester) async {
      await boot(tester);
      await addPatient(tester, 'Mom');

      // Seed two medicines through the provider — the form path is covered by
      // the test above; this one is about search and the order projection.
      final context = tester.element(find.text('Medstock'));
      final app = Provider.of<AppProvider>(context, listen: false);
      final mom = app.patients.single;

      await tester.runAsync(() async {
        for (final (name, strength, stock) in [
          ('Lithosun SR', '400mg', 10.0),
          ('Nexito', '10mg', 0.0),
        ]) {
          await app.addMedicine(_medicine(name, strength, stock, mom.id!));
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Lithosun SR 400mg'), findsOneWidget);
      expect(find.text('Nexito 10mg'), findsOneWidget);

      // --- search ---
      await tester.enterText(find.byType(TextField).first, 'nexito');
      await tester.pumpAndSettle();
      expect(find.text('Nexito 10mg'), findsOneWidget);
      expect(find.text('Lithosun SR 400mg'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      // --- order tab ---
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.text('No orders yet'), findsOneWidget);

      // Build a draft 30 days out directly, then create it through the UI.
      final target = DateTime.now().add(const Duration(days: 29));
      final draftItems = app.buildDraft(target);

      // 1/day each: Lithosun needs 30 − 10 = 20, Nexito needs 30 − 0 = 30.
      expect(draftItems.length, 2);
      expect(
        draftItems.firstWhere((i) => i.medicineName == 'Lithosun SR 400mg').qty,
        20,
      );
      expect(
        draftItems.firstWhere((i) => i.medicineName == 'Nexito 10mg').qty,
        30,
      );

      await tester.runAsync(() async {
        await app.createOrder(targetDate: target, items: draftItems);
      });
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsNothing);
      expect(find.textContaining('2 medicines'), findsWidgets);

      // --- open it and check the WhatsApp message preview ---
      await tester.tap(find.textContaining('Until ').first);
      await tester.pumpAndSettle();

      expect(find.text('MESSAGE PREVIEW'), findsOneWidget);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      expect(find.textContaining('Lithosun SR 400mg\n20 tablets'), findsOneWidget);
    });

    testWidgets('receiving an order tops the stock back up', (tester) async {
      await boot(tester);
      await addPatient(tester, 'Mom');

      final context = tester.element(find.text('Medstock'));
      final app = Provider.of<AppProvider>(context, listen: false);
      final mom = app.patients.single;

      await tester.runAsync(() async {
        await app.addMedicine(_medicine('Dytor', '5', 2, mom.id!));
        final target = DateTime.now().add(const Duration(days: 9));
        await app.createOrder(
          targetDate: target,
          items: app.buildDraft(target),
        );
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Until ').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark received & add to stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to stock'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Received'), findsWidgets);

      // 2 on hand + 8 ordered = 10, which is exactly the 10-day window.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 tablets in stock'), findsOneWidget);
    });
  });
}
