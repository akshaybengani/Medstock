import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../components/app_drawer.dart';
import '../../components/atom/loading_atom.dart';
import '../../components/dialogs/theme_picker_sheet.dart';
import '../../components/atom/textfield_atom.dart';
import '../../constants.dart';
import '../../models/medicine.dart';
import '../../models/patient.dart';
import '../../providers/app_provider.dart';
import '../../providers/theme_provider.dart';
import '../medicine/medicine_detail_screen.dart';
import '../medicine/medicine_form_screen.dart';
import '../patients/patients_screen.dart';
import 'medicine_card.dart';

/// The stock book: a search field, one tab per patient plus "All", and a
/// scrollable list of medicine cards per tab.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  TabController? _tabController;
  int _tabCount = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  /// The tab row is derived from the patient list, so the controller has to be
  /// rebuilt whenever a patient is added or removed. The selected index is
  /// preserved where it still exists.
  ///
  /// The outgoing controller is disposed after the frame rather than inline:
  /// the TabBar and TabBarView still hold it while this build runs, and
  /// tearing it down underneath them can fire an in-flight animation against
  /// a disposed controller.
  void _syncTabController(int count) {
    if (_tabController != null && _tabCount == count) return;

    final previous = _tabController;
    final index = previous?.index ?? 0;

    _tabController = TabController(
      length: count,
      vsync: this,
      initialIndex: index < count ? index : 0,
    );
    _tabCount = count;

    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final patients = provider.patients;

    // Tab 0 is "All"; the rest map 1:1 onto patients.
    _syncTabController(patients.length + 1);
    final controller = _tabController!;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text(K.appName),
        actions: [
          IconButton(
            icon: Icon(context.watch<ThemeProvider>().icon),
            tooltip: 'Appearance: ${context.watch<ThemeProvider>().label}',
            onPressed: () => ThemePickerSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Manage patients',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PatientsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Dashboard and Orders are both mounted inside HomeShell's
        // IndexedStack, so their FABs need distinct hero tags.
        heroTag: 'fab-add-medicine',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MedicineFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Medicine'),
      ),
      body: provider.loading
          ? const LoadingAtom(message: 'Opening your stock book…')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: AppSearchField(
                    controller: _searchController,
                    onChanged: provider.setSearch,
                  ),
                ),
                _SummaryStrip(provider: provider),
                if (patients.isNotEmpty)
                  _PatientTabBar(controller: controller, patients: patients),
                Expanded(
                  child: patients.isEmpty
                      ? _MedicineList(
                          medicines: provider.medicinesFor(null),
                          patientsById: _byId(patients),
                          patientId: null,
                          searchActive: provider.search.trim().isNotEmpty,
                        )
                      : TabBarView(
                          controller: controller,
                          children: [
                            _MedicineList(
                              medicines: provider.medicinesFor(null),
                              patientsById: _byId(patients),
                              patientId: null,
                              searchActive:
                                  provider.search.trim().isNotEmpty,
                            ),
                            for (final patient in patients)
                              _MedicineList(
                                medicines:
                                    provider.medicinesFor(patient.id),
                                patientsById: _byId(patients),
                                patientId: patient.id,
                                patientName: patient.name,
                                searchActive:
                                    provider.search.trim().isNotEmpty,
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Map<int, Patient> _byId(List<Patient> patients) => {
        for (final p in patients)
          if (p.id != null) p.id!: p,
      };
}

/// Rounded pill tab bar: "All" followed by each patient.
class _PatientTabBar extends StatelessWidget {
  const _PatientTabBar({required this.controller, required this.patients});

  final TabController controller;
  final List<Patient> patients;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.all(4),
        indicatorPadding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        indicator: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(18),
        ),
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        tabs: [
          const _PillTab(label: 'All'),
          for (final patient in patients) _PillTab(label: patient.name),
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label),
      ),
    );
  }
}

/// Compact "3 medicines need a refill" strip above the tabs.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.provider});
  final AppProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final total = provider.medicines.length;
    if (total == 0) return const SizedBox.shrink();

    final attention = provider.needsAttention.length;
    final soonest = provider.soonestRunOut;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Icon(
            attention > 0
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            size: 16,
            color: attention > 0 ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              attention > 0
                  ? '$attention of $total ${total == 1 ? 'medicine' : 'medicines'} need a refill'
                  : 'All $total ${total == 1 ? 'medicine' : 'medicines'} well stocked',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (soonest != null)
            Text(
              'Next: ${soonest.$2.coverageLabel.toLowerCase()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _MedicineList extends StatelessWidget {
  const _MedicineList({
    required this.medicines,
    required this.patientsById,
    required this.patientId,
    required this.searchActive,
    this.patientName,
  });

  final List<Medicine> medicines;
  final Map<int, Patient> patientsById;
  final int? patientId;
  final String? patientName;
  final bool searchActive;

  @override
  Widget build(BuildContext context) {
    if (medicines.isEmpty) {
      if (searchActive) {
        return const EmptyState(
          icon: Icons.search_off,
          title: 'Nothing matches that search',
          message:
              'Medstock looks through names, types, notes, prescriptions and '
              'patient names.',
        );
      }

      if (patientId != null) {
        return EmptyState(
          icon: Icons.medication_outlined,
          title: 'No medicines for ${patientName ?? 'this patient'}',
          message:
              'Attach ${patientName ?? 'them'} to a medicine and their dosage '
              'will show up here.',
        );
      }

      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Your stock book is empty',
        message:
            'Add the first medicine and Medstock will track what is left and '
            'when to reorder.',
        actionLabel: 'Add medicine',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MedicineFormScreen()),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: medicines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final medicine = medicines[index];
        return MedicineCard(
          medicine: medicine,
          patientsById: patientsById,
          patientId: patientId,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MedicineDetailScreen(medicineId: medicine.id!),
            ),
          ),
        );
      },
    );
  }
}
