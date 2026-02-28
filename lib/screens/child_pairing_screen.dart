import 'package:flutter/material.dart';

import 'child/parent_link_screen.dart';

/// Backward-compatible wrapper for older routes.
/// The active pairing flow lives in `ParentLinkScreen`.
class ChildPairingScreen extends StatelessWidget {
  const ChildPairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ParentLinkScreen();
  }
}
