// lib/features/ventas/presentation/screens/checkout_crm_screen.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../controllers/cart_controller.dart';

/// Pantalla Placeholder de Micro-CRM y Checkout (HU-3.4).
/// Punto de entrada para la búsqueda/creación de clientes y emisión de órdenes de venta.
class CheckoutCrmScreen extends StatelessWidget {
  const CheckoutCrmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Volver',
        ),
        title: Text('Micro-CRM y Checkout', style: AppTypography.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppPalette.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.person_search_outlined,
                  size: 38,
                  color: AppPalette.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Micro-CRM y Flujo de Cobro',
                style: AppTypography.headline.copyWith(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'En el próximo sprint se implementará la búsqueda de clientes por RUT/Nombre, selección de medio de pago y emisión de la Orden de Venta.',
                style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 18, color: AppPalette.secondary),
                    const SizedBox(width: 8),
                    Text(
                      'Total a cobrar: ${CartController.instance.totalMontoFormateado}',
                      style: AppTypography.body.copyWith(
                        color: AppPalette.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
