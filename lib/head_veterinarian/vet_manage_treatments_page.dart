import 'package:flutter/material.dart';

import '../expert/treatment_editor.dart';
import 'treatment_approvals_page.dart';

/// Head veterinarian "Manage Treatments" hub:
/// - Tab 1: Manage (direct publish to farmers; no approval needed for vet's own edits)
/// - Tab 2: Approvals (approve/delete expert proposals)
class VetManageTreatmentsPage extends StatelessWidget {
  const VetManageTreatmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Column(
          children: [
            Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const TabBar(
                  labelColor: Colors.green,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: Colors.green,
                  tabs: [
                    Tab(text: 'Manage'),
                    Tab(text: 'Approvals'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Expanded(
              child: TabBarView(
                children: [
                  // Vet edits go live immediately (no approval needed)
                  TreatmentEditorPage(directPublish: true, showPending: false),
                  // Vet approves/deletes expert proposals
                  TreatmentApprovalsPage(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


