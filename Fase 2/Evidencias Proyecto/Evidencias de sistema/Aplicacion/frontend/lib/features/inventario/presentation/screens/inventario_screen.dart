// lib/features/inventario/presentation/screens/inventario_screen.dart
// Export y alias para conformar con la nomenclatura de SPEC-HU-TAREA-16

export 'buscador_screen.dart';

import 'package:flutter/material.dart';
import 'buscador_screen.dart';

/// Alias widget para BuscadorScreen acorde a la especificación SPEC-HU-TAREA-16.
class InventarioScreen extends StatelessWidget {
  const InventarioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const BuscadorScreen();
  }
}
