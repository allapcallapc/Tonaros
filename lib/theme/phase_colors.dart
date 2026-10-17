import 'package:flutter/material.dart';

import '../engine/session_plan.dart';

/// Each phase's color, shared by the running screen and the editor's
/// exercise badges. Hold exercises read pink, Tempo exercises violet.
abstract final class PhaseColors {
  static const hold1 = Color(0xFFE91E63); // pink
  static const hold2 = Color(0xFFFF7A1A); // orange
  static const rest = Color(0xFF00A99D); // teal
  static const move = Color(0xFF7E57C2); // violet
  static const tempoHold = Color(0xFFFFB300); // amber
  static const back = Color(0xFF9575CD); // light violet, pairs with move
  static const getReady = Color(0xFF5E5BC9); // brand purple
  static const transition = Color(0xFF607D8B); // blue grey

  static Color of(PhaseKind kind) => switch (kind) {
        PhaseKind.getReady => getReady,
        PhaseKind.hold1 => hold1,
        PhaseKind.hold2 => hold2,
        PhaseKind.rest || PhaseKind.setRest => rest,
        PhaseKind.move => move,
        PhaseKind.tempoHold => tempoHold,
        PhaseKind.back => back,
        PhaseKind.transition || PhaseKind.waitForTap => transition,
      };
}
