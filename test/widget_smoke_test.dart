import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medstock/helpers/date_helpers.dart';
import 'package:medstock/models/dose_assignment.dart';
import 'package:medstock/models/medicine.dart';
import 'package:medstock/providers/app_provider.dart';
import 'package:medstock/providers/theme_provider.dart';
import 'package:medstock/constants.dart';
import 'package:medstock/screens/home_shell.dart';
import 'package:medstock/screens/medicine/medicine_detail_screen.dart';
import 'package:medstock/screens/medicine/medicine_form_screen.dart';
import 'package:medstock/screens/orders/order_draft_screen.dart';
import 'package:medstock/screens/orders/orders_screen.dart';
import 'package:medstock/services/database_service.dart';
import 'package:medstock/theme/theme_data.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders the real screens against a real in-memory database to catch build
/// and layout errors that pure logic tests cannot see.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.pathOverride = inMemoryDatabasePath;
  });

  late AppProvider app;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.close();
    app = AppProvider();
    await app.load();
  });

  /// The screens read both providers, so the test host supplies both.
  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: child),
      );

  /// Seeds through the real database. Must be wrapped in `tester.runAsync`
  /// at the call site: testWidgets installs a fake-async zone, and awaiting
  /// real sqflite I/O inside it deadlocks.
  Future<void> seed() async {
    final mom = await app.addPatient('Mom');
    final dad = await app.addPatient('Dad');
    final now = DateTime.now();

    await app.addMedicine(Medicine(
      name: 'Dytor',
      strength: '5',
      stockQty: 60,
      stockAsOf: Dates.today(),
      description: 'Blood pressure',
      prescribedBy: 'Dr. Sharma',
      createdAt: now,
      updatedAt: now,
      assignments: [
        DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
        DoseAssignment(
          patientId: dad.id!,
          intakesPerDay: 2,
          startDate: Dates.today(),
        ),
      ],
    ));

    // Low stock, so the attention path renders too.
    await app.addMedicine(Medicine(
      name: 'Nexito',
      strength: '10mg',
      stockQty: 2,
      stockAsOf: Dates.today(),
      createdAt: now,
      updatedAt: now,
      assignments: [
        DoseAssignment(patientId: mom.id!, startDate: Dates.today()),
      ],
    ));
  }

  testWidgets('empty dashboard shows the first-run empty state',
      (tester) async {
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    expect(find.text('Medstock'), findsOneWidget);
    expect(find.text('Your stock book is empty'), findsOneWidget);
    // No patients yet, so no tab row.
    expect(find.text('All'), findsNothing);
  });

  testWidgets('dashboard renders the dynamic tab row and card totals',
      (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    // "All" plus one tab per patient.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Mom'), findsWidgets);
    expect(find.text('Dad'), findsWidgets);

    // Household total for the shared medicine is 3/day.
    expect(find.text('3 tablets / day'), findsOneWidget);
    expect(find.textContaining('60 tablets in stock'), findsOneWidget);

    // Low stock floats to the top and is flagged.
    expect(find.textContaining('a refill'), findsOneWidget);
  });

  testWidgets('a patient tab shows only that patient\'s dose', (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    // Switch to Dad, who takes Dytor twice a day and no Nexito.
    await tester.tap(find.text('Dad').last);
    await tester.pumpAndSettle();

    expect(find.text('2 tablets / day'), findsOneWidget);
    expect(find.text('Dytor 5'), findsOneWidget);
    expect(find.text('Nexito 10mg'), findsNothing);
  });

  testWidgets('search filters the list live', (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'nexito');
    await tester.pumpAndSettle();

    expect(find.text('Nexito 10mg'), findsOneWidget);
    expect(find.text('Dytor 5'), findsNothing);

    // A term that only appears in a detail field still matches.
    await tester.enterText(find.byType(TextField).first, 'sharma');
    await tester.pumpAndSettle();
    expect(find.text('Dytor 5'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches that search'), findsOneWidget);
  });

  testWidgets('medicine detail renders stock, dosage and extra fields',
      (tester) async {
    await tester.runAsync(seed);
    final dytor = app.medicines.firstWhere((m) => m.name == 'Dytor');

    await tester.pumpWidget(host(MedicineDetailScreen(medicineId: dytor.id!)));
    await tester.pumpAndSettle();

    expect(find.text('Dytor 5'), findsOneWidget);
    expect(find.text('60'), findsOneWidget); // the big remaining figure
    expect(find.text('Household total'), findsOneWidget);
    expect(find.text('Add stock'), findsOneWidget);

    // The additional-information card is below the fold of the lazy list.
    await tester.dragUntilVisible(
      find.text('Blood pressure'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Blood pressure'), findsOneWidget);
    expect(find.text('Dr. Sharma'), findsOneWidget);
  });

  testWidgets('medicine form builds, expands and validates', (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const MedicineFormScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Add medicine'), findsOneWidget);
    expect(find.text('PATIENTS & DOSAGE'), findsOneWidget);

    // Saving with no name must surface the one required-field error.
    await tester.tap(find.text('Save medicine'));
    await tester.pumpAndSettle();
    expect(find.text('Medicine name is required'), findsOneWidget);

    // The additional-information section opens.
    await tester.dragUntilVisible(
      find.text('Additional information'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Additional information'));
    await tester.pumpAndSettle();
    expect(find.text('Prescribed by'), findsWidgets);
  });

  testWidgets('toggling a patient on reveals the dose controls',
      (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const MedicineFormScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Each dose'), findsNothing);

    await tester.dragUntilVisible(
      find.byType(Switch).first,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Each dose'), findsOneWidget);
    expect(find.text('Times a day'), findsOneWidget);
    // The running household total appears once a dosage exists.
    expect(find.textContaining('Total 1 tablet / day'), findsOneWidget);
  });

  testWidgets('orders tab renders its empty state', (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const OrdersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('No orders yet'), findsOneWidget);
  });

  testWidgets('bottom navigation switches between the two tabs',
      (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    expect(find.text('No orders yet'), findsOneWidget);
  });

  testWidgets('adding a patient grows the tab row', (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    await tester.runAsync(() => app.addPatient('Dada ji'));
    await tester.pumpAndSettle();

    expect(find.text('Dada ji'), findsWidgets);
  });

  group('narrow phone layout', () {
    /// 360×640 logical pixels — a small Android phone. Overflows that the
    /// default 800×600 test surface hides show up here.
    Future<void> asPhone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('dashboard fits without overflowing', (tester) async {
      await asPhone(tester);
      await tester.runAsync(seed);
      // A long name and a third patient stress the card and the tab row.
      await tester.runAsync(() async {
        final gp = await app.addPatient('Dada ji');
        final now = DateTime.now();
        await app.addMedicine(Medicine(
          name: 'Nourobion Forte Sustained Release',
          strength: '500mg + B12',
          stockQty: 5,
          stockAsOf: Dates.today(),
          createdAt: now,
          updatedAt: now,
          assignments: [
            DoseAssignment(
              patientId: gp.id!,
              qtyPerIntake: 1.5,
              intakesPerDay: 3,
              startDate: Dates.today(),
            ),
          ],
        ));
      });

      await tester.pumpWidget(host(const HomeShell()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('medicine form fits without overflowing', (tester) async {
      await asPhone(tester);
      await tester.runAsync(seed);

      await tester.pumpWidget(host(const MedicineFormScreen()));
      await tester.pumpAndSettle();

      // Open every conditional branch of the form.
      await tester.dragUntilVisible(
        find.byType(Switch).first,
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Each dose'), findsOneWidget);
    });

    testWidgets('medicine detail fits without overflowing', (tester) async {
      await asPhone(tester);
      await tester.runAsync(seed);
      final dytor = app.medicines.firstWhere((m) => m.name == 'Dytor');

      await tester.pumpWidget(host(MedicineDetailScreen(medicineId: dytor.id!)));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('order draft fits without overflowing', (tester) async {
      await asPhone(tester);
      await tester.runAsync(seed);

      await tester.pumpWidget(host(
        OrderDraftScreen(targetDate: Dates.today().add(const Duration(days: 30))),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Both seeded medicines need topping up over a 31-day window.
      expect(find.text('Dytor 5'), findsOneWidget);
      expect(find.text('Nexito 10mg'), findsOneWidget);
    });
  });

  testWidgets('pushing a route from the shell does not collide hero tags',
      (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(host(const HomeShell()));
    await tester.pumpAndSettle();

    // Dashboard and Orders are both mounted, so both FABs exist at once.
    // Pushing a route makes Flutter search the outgoing subtree for heroes,
    // which asserts if two share the default FloatingActionButton tag.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Medicine'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Add medicine'), findsOneWidget);
  });

  group('appearance toggle', () {
    testWidgets('app bar opens the picker and switching mode sticks',
        (tester) async {
      await tester.runAsync(seed);
      final theme = ThemeProvider();

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          home: const HomeShell(),
        ),
      ));
      await tester.pumpAndSettle();

      // Starts on "match device".
      expect(theme.mode, ThemeMode.system);
      expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.brightness_auto_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Match device'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(theme.mode, ThemeMode.dark);
      // The sheet closes itself once a choice is made.
      expect(find.text('Appearance'), findsNothing);
    });

    testWidgets('dark theme renders the dashboard without errors',
        (tester) async {
      await tester.runAsync(seed);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const HomeShell(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Dytor 5'), findsOneWidget);
    });
  });

  group('eye drops and other continuous items', () {
    testWidgets('picking Drops defaults the dosage to "lasts N days"',
        (tester) async {
      await tester.runAsync(seed);
      await tester.pumpWidget(host(const MedicineFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Medicine name'),
        'Refresh Tears',
      );

      // Switch the type to Drops.
      await tester.tap(find.byType(DropdownButtonFormField<MedicineType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drops').last);
      await tester.pumpAndSettle();

      // Attach a patient — the editor should land in duration mode.
      await tester.dragUntilVisible(
        find.byType(Switch).first,
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.text('Lasts (days)'), findsOneWidget);
      expect(find.text('Units at a time'), findsOneWidget);
      // Not a per-day medicine, so this stepper is gone.
      expect(find.text('Times a day'), findsNothing);
      expect(find.textContaining('lasts 30 days'), findsWidgets);
      expect(find.textContaining('Total 1 bottle / 30 days'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the card reads in bottles per month, not fractions per day',
        (tester) async {
      final mom = await tester.runAsync(() => app.addPatient('Mom'));
      final now = DateTime.now();

      await tester.runAsync(() => app.addMedicine(Medicine(
            name: 'Refresh Tears',
            type: MedicineType.drops,
            stockQty: 1,
            stockAsOf: Dates.today(),
            createdAt: now,
            updatedAt: now,
            assignments: [
              DoseAssignment(
                patientId: mom!.id!,
                scheduleType: ScheduleType.perDuration,
                intervalDays: 30,
                startDate: Dates.today(),
              ),
            ],
          )));

      await tester.pumpWidget(host(const HomeShell()));
      await tester.pumpAndSettle();

      expect(find.text('1 bottle / 30 days'), findsOneWidget);
      expect(find.textContaining('1 bottle in stock'), findsOneWidget);
      expect(find.text('30 days left'), findsOneWidget);
      // The misleading fractional figure must not appear anywhere.
      expect(find.textContaining('0.03'), findsNothing);
    });
  });

  group('pack pricing validation', () {
    /// Opens the form and reveals the price field, which lives in the
    /// collapsible "Additional information" block.
    Future<void> openPricing(WidgetTester tester) async {
      await tester.pumpWidget(host(const MedicineFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Medicine name'),
        'Dytor',
      );
      await tester.dragUntilVisible(
        find.text('Additional information'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Additional information'));
      await tester.pumpAndSettle();
    }

    testWidgets('the price field asks for a pack price, not a unit price',
        (tester) async {
      await tester.runAsync(seed);
      await openPricing(tester);

      expect(find.widgetWithText(TextFormField, 'Price per strip / pack'),
          findsOneWidget);
      expect(find.textContaining('Price per tablet'), findsNothing);
    });

    testWidgets('entering a price makes pack size mandatory', (tester) async {
      await tester.runAsync(seed);
      final before = app.medicines.length;
      await openPricing(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price per strip / pack'),
        '25',
      );
      await tester.pumpAndSettle();

      // The pack size label gains its required marker.
      await tester.dragUntilVisible(
        find.text('CURRENT STOCK'),
        find.byType(Scrollable).first,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Pack size *'), findsOneWidget);

      // Saving is refused with an explanation rather than silently costing
      // nothing.
      await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Needed to work out the price per tablet'),
        findsOneWidget,
      );
      // Nothing was written.
      expect(app.medicines.length, before);
    });

    testWidgets('with a pack size it saves and shows the per-unit cost',
        (tester) async {
      await tester.runAsync(seed);
      await openPricing(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price per strip / pack'),
        '25',
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('CURRENT STOCK'),
        find.byType(Scrollable).first,
        const Offset(0, 200),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Pack size *'),
        '10',
      );
      await tester.pumpAndSettle();

      // The form spells out what a pack price means per tablet.
      await tester.dragUntilVisible(
        find.textContaining('per tablet'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('₹2.50 per tablet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a price alone is still allowed when left blank',
        (tester) async {
      await tester.runAsync(seed);
      await openPricing(tester);

      // No price typed, so pack size stays optional and the form saves.
      expect(find.widgetWithText(TextFormField, 'Pack size'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Pack size *'), findsNothing);
    });
  });

  group('pricing rule holds regardless of scroll position', () {
    /// This is the case that slipped through on a real device: the form was a
    /// lazy ListView, so scrolling down to the price field disposed the pack
    /// size field, which unregistered it from the Form — and validate() then
    /// silently skipped its validator, saving a priced medicine with no pack
    /// size. The fix keeps every field mounted, plus an explicit guard in
    /// _save() so the rule does not depend on layout at all.
    testWidgets('saving with the pack size field scrolled away is refused',
        (tester) async {
      await tester.runAsync(seed);
      final before = app.medicines.length;

      // A short surface makes it certain that the two fields cannot both be
      // visible at once.
      tester.view.physicalSize = const Size(360 * 3, 560 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(const MedicineFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Medicine name'),
        'Dytor',
      );
      await tester.pumpAndSettle();

      // Reveal and fill the price, which lives well below the pack size.
      await tester.dragUntilVisible(
        find.text('Additional information'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Additional information'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Price per strip / pack'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price per strip / pack'),
        '25',
      );
      await tester.pumpAndSettle();

      // Pack size is now off-screen. Save from here, without scrolling back.
      await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
      await tester.pumpAndSettle();

      // Nothing written, and the reason is stated.
      expect(app.medicines.length, before);
      expect(
        find.textContaining('needed to work out the price per tablet'),
        findsOneWidget,
      );
    });

    testWidgets('the field stays registered while scrolled out of view',
        (tester) async {
      await tester.runAsync(seed);
      tester.view.physicalSize = const Size(360 * 3, 560 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(const MedicineFormScreen()));
      await tester.pumpAndSettle();

      // Scroll to the very bottom of the form.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();

      // The pack size field is still in the tree, so its validator still runs.
      expect(
        find.widgetWithText(TextFormField, 'Pack size', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('validation feedback clears itself', () {
    testWidgets('fixing the pack size clears its error without saving again',
        (tester) async {
      await tester.runAsync(seed);
      await tester.pumpWidget(host(const MedicineFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Medicine name'),
        'Dytor',
      );
      await tester.dragUntilVisible(
        find.text('Additional information'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Additional information'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price per strip / pack'),
        '25',
      );
      await tester.pumpAndSettle();

      // Provoke the error. Match the field's own message exactly — the
      // SnackBar carries similar wording and would otherwise satisfy this.
      const inlineError = 'Needed to work out the price per tablet';
      await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
      await tester.pump();
      expect(find.text(inlineError), findsOneWidget);

      // Typing a valid pack size clears it straight away.
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Pack size *'),
        find.byType(Scrollable).first,
        const Offset(0, 200),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Pack size *'),
        '10',
      );
      await tester.pumpAndSettle();

      expect(find.text(inlineError), findsNothing);
    });

    testWidgets('the refill count agrees with its verb', (tester) async {
      final mom = await tester.runAsync(() => app.addPatient('Mom'));
      final now = DateTime.now();
      await tester.runAsync(() => app.addMedicine(Medicine(
            name: 'Nexito',
            stockQty: 1,
            stockAsOf: Dates.today(),
            createdAt: now,
            updatedAt: now,
            assignments: [
              DoseAssignment(patientId: mom!.id!, startDate: Dates.today()),
            ],
          )));

      await tester.pumpWidget(host(const HomeShell()));
      await tester.pumpAndSettle();

      // Exactly one medicine, exactly one needing attention.
      expect(find.text('1 of 1 medicine needs a refill'), findsOneWidget);
    });
  });
}
