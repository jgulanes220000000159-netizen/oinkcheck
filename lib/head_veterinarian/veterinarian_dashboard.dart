import 'package:flutter/material.dart';

import '../expert/expert_dashboard.dart';

/// Head veterinarian uses the same UI/flows as Expert.
/// The only difference: the "Manage Treatments" tab becomes an approvals screen
/// where the vet can approve or delete expert treatment proposals.
class VeterinarianDashboard extends StatelessWidget {
  const VeterinarianDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // ExpertDashboard will auto-detect role from Hive userProfile.role and
    // swap only the Treatments tab when role == veterinarian/head_veterinarian.
    return const ExpertDashboard();
  }
}


