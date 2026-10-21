// lib/features/paletizado/domain/models/etiqueta_data.dart
//
// HU-2.4 — Modelo de dominio para la etiqueta térmica.
//
// Responsabilidad única: transportar los datos necesarios para renderizar
// el widget EtiquetaTermicaWidget y enviarlos al servicio de impresión.
//
// Regla de negocio: todos los campos que puedan ser nulos (ej. cilindrada, tracción)
// se exponen como String? y el widget los convierte a "N/A" en la UI.

import 'package:flutter/foundation.dart';

/// Modelo inmutable con todos los datos de una etiqueta de activo inventariado.
class EtiquetaData {
  // ── Identificación del activo en BD (HU-2.4 Fase 4 — PATCH de confirmación) ─
  /// UUID del Activo_Inventariado. Requerido para confirmar impresión en el backend.
  final String idActivo;

  // ── Identificación del vehículo origen ──────────────────────────────────
  final String numeroIngreso;
  final String marca;
  final String modelo;
  final int anio;

  // ── Detalles técnicos del activo (null → se muestra "N/A") ──────────────
  final String? cilindrada;
  final String? combustible;
  final String? transmision;
  final String? numeroMotor;
  final String? traccion;

  // ── Ubicación física en el almacén ───────────────────────────────────────
  final String galpon;
  final String pasillo;
  final String pallet;

  // ── Identidad digital (HU-2.4) ───────────────────────────────────────────
  /// Contenido del código QR. Ejemplo: "MOT-8A2F"
  final String skuQrFisico;

  const EtiquetaData({
    required this.idActivo,
    required this.numeroIngreso,
    required this.marca,
    required this.modelo,
    required this.anio,
    this.cilindrada,
    this.combustible,
    this.transmision,
    this.numeroMotor,
    this.traccion,
    required this.galpon,
    required this.pasillo,
    required this.pallet,
    required this.skuQrFisico,
  });

  /// Factory unificado (Single Source of Truth) para instanciar EtiquetaData
  /// desde cualquier pantalla o endpoint (Paletizado, Detalle de Inventario, Alertas).
  ///
  /// Resuelve discrepancias de llaves (ej: sku vs sku_qr_fisico, numero_motor ausente)
  /// y desanida estructuras jerárquicas (vehiculo / motor / caja_cambios).
  factory EtiquetaData.fromMap(Map<String, dynamic> raw) {
    debugPrint("📥 [EtiquetaData.fromMap] Unificando datos de etiqueta: $raw");

    // Desanidar si viene envuelto en "data", "activo" o "resultado"
    final Map<String, dynamic> data = raw.containsKey('data') && raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : (raw.containsKey('activo') && raw['activo'] is Map<String, dynamic>
            ? raw['activo'] as Map<String, dynamic>
            : raw);

    // Mapeo defensivo de vehículos o bloques técnicos anidados
    final vehiculo = data['vehiculo'] is Map<String, dynamic> ? data['vehiculo'] as Map<String, dynamic> : null;
    final motor = data['motor'] is Map<String, dynamic> ? data['motor'] as Map<String, dynamic> : null;
    final caja = data['caja_cambios'] is Map<String, dynamic> ? data['caja_cambios'] as Map<String, dynamic> : null;

    final idActivo = (data['id_activo'] ?? data['id'] ?? motor?['id_activo'] ?? caja?['id_activo'])?.toString() ?? '';
    final numeroIngreso = (data['numero_ingreso'] ?? vehiculo?['numero_ingreso'])?.toString() ?? 'N/A';
    final marca = (data['marca'] ?? vehiculo?['marca'])?.toString() ?? 'Desconocida';
    final modelo = (data['modelo'] ?? vehiculo?['modelo'])?.toString() ?? 'Desconocido';
    final anio = (data['anio'] ?? vehiculo?['anio'] as num?)?.toInt() ?? 0;

    final cilindradaRaw = (data['cilindrada'] ?? motor?['cilindrada'] ?? caja?['cilindrada'])?.toString();
    final combustibleRaw = (data['combustible'] ?? motor?['combustible'] ?? caja?['combustible'])?.toString();
    final transmisionRaw = (data['transmision'] ?? data['transmision_tipo'] ?? motor?['transmision_tipo'] ?? caja?['transmision_tipo'])?.toString();
    final numeroMotorRaw = (data['numero_motor'] ?? motor?['numero_motor'])?.toString();
    final traccionRaw = (data['traccion'] ?? data['tipo_traccion'] ?? vehiculo?['traccion'] ?? motor?['traccion'] ?? caja?['traccion'])?.toString();

    final galpon = (data['galpon'] ?? data['ubicacion_galpon'])?.toString() ?? '';
    final pasillo = (data['pasillo'] ?? data['ubicacion_pasillo'])?.toString() ?? '';
    final pallet = (data['pallet'] ?? data['ubicacion_pallet'])?.toString() ?? '';
    final skuQrFisico = (data['sku_qr_fisico'] ?? data['sku'])?.toString() ?? '';

    return EtiquetaData(
      idActivo: idActivo,
      numeroIngreso: numeroIngreso,
      marca: marca,
      modelo: modelo,
      anio: anio,
      cilindrada: _limpiarValor(cilindradaRaw),
      combustible: _limpiarValor(combustibleRaw),
      transmision: _limpiarValor(transmisionRaw),
      numeroMotor: _limpiarValor(numeroMotorRaw),
      traccion: _limpiarValor(traccionRaw),
      galpon: galpon,
      pasillo: pasillo,
      pallet: pallet,
      skuQrFisico: skuQrFisico,
    );
  }

  /// Alias de compatibilidad hacia [fromMap].
  factory EtiquetaData.fromJson(Map<String, dynamic> json) => EtiquetaData.fromMap(json);

  /// Helper defensivo para convertir valores vacíos o no asignados a null
  static String? _limpiarValor(String? val) {
    if (val == null) return null;
    final trimmed = val.trim();
    if (trimmed.isEmpty ||
        trimmed.toUpperCase() == 'N/A' ||
        trimmed.toUpperCase() == 'S/A' ||
        trimmed.toUpperCase() == 'NULL') {
      return null;
    }
    return trimmed;
  }

  /// Helper: devuelve el valor o "N/A" si el campo es nulo o vacío.
  /// Conveniente para la capa de presentación.
  static String naIfNull(String? value) =>
      (value == null || value.trim().isEmpty) ? 'N/A' : value;
}
