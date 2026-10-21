import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/paletizado/domain/models/etiqueta_data.dart';
import 'package:frontend/features/paletizado/services/zpl_builder.dart';

void main() {
  group('ZplBuilder - Validación de Espejo ZPL II (800x560 dots @ 203 DPI)', () {
    test('Etiqueta de Motor genera ZPL con 7 campos, badge MOTOR y footer dual', () {
      final motorData = EtiquetaData(
        idActivo: 'act-mot-001',
        skuQrFisico: 'MOT-2024-001',
        marca: 'Toyota',
        modelo: 'Hilux',
        anio: 2021,
        cilindrada: '2.8L',
        combustible: 'Diesel',
        transmision: 'Manual',
        traccion: '4x4',
        numeroMotor: '1GD-FTV-9988',
        numeroIngreso: 'ING-5542',
        galpon: 'G1',
        pasillo: 'P03',
        pallet: 'PAL-12',
      );

      final zpl = ZplBuilder.buildEtiquetaActivo(motorData);

      // Dimensiones de lienzo
      expect(zpl, contains('^PW800'));
      expect(zpl, contains('^LL560'));

      // Marco y divisores estructurales (mismas coordenadas que EtiquetaTermicaWidget)
      expect(zpl, contains('^FO20,15^GB760,530,3^FS'));
      expect(zpl, contains('^FO20,95^GB760,0,3^FS'));
      expect(zpl, contains('^FO20,455^GB760,0,3^FS'));
      expect(zpl, contains('^FO360,95^GB0,360,3^FS'));

      // Header
      expect(zpl, contains('^FO40,25^A0N,32,32^FDCRESAL^FS'));
      expect(zpl, contains('^FO40,62^A0N,20,20^FDDesarme . Vehiculos . Repuestos^FS'));
      expect(zpl, contains('^FO500,25^GB260,55,55^FS'));
      expect(zpl, contains('^FDMOTOR^FS'));

      // Panel izquierdo
      expect(zpl, contains('^FO100,120^BQN,2,8^FDQA,MOT-2024-001^FS'));
      expect(zpl, contains('^FO35,342^A0N,26,26^FB310,1,0,C^FDMOT-2024-001^FS'));
      expect(zpl, contains('^FO35,384^GB310,50,50^FS'));
      expect(zpl, contains('GAL: G1 | PAS: P03 | PAL: PAL-12'));

      // 7 campos técnicos unificados
      expect(zpl, contains('^FO385,118^A0N,25,25^FDMARCA: TOYOTA^FS'));
      expect(zpl, contains('^FO385,164^A0N,25,25^FDMODELO: HILUX^FS'));
      expect(zpl, contains('^FO385,210^A0N,25,25^FDAÑO: 2021^FS'));
      expect(zpl, contains('^FO385,256^A0N,25,25^FDCILINDRADA: 2.8L^FS'));
      expect(zpl, contains('^FO385,302^A0N,25,25^FDCOMBUSTIBLE: DIESEL^FS'));
      expect(zpl, contains('^FO385,348^A0N,25,25^FDTRANSMISION: MANUAL^FS'));
      expect(zpl, contains('^FO385,394^A0N,25,25^FDTRACCION: 4X4^FS'));

      // Footer Motor
      expect(zpl, contains('^FO35,485^A0N,24,24^FDNRO MOTOR: 1GD-FTV-9988^FS'));
      expect(zpl, contains('^FO430,485^A0N,24,24^FDNRO INGRESO: ING-5542^FS'));
    });

    test('Etiqueta de Caja de Cambios genera ZPL con badge CAJAS DE CAMBIO y footer único', () {
      final cajaData = EtiquetaData(
        idActivo: 'act-caj-001',
        skuQrFisico: 'CAJ-2024-099',
        marca: 'Chevrolet',
        modelo: 'D-Max',
        anio: 2020,
        cilindrada: '2.5L',
        combustible: 'Diesel',
        transmision: 'Automatica',
        traccion: '4x2',
        numeroMotor: null,
        numeroIngreso: 'ING-8821',
        galpon: '',
        pasillo: '',
        pallet: '',
      );

      final zpl = ZplBuilder.buildEtiquetaActivo(cajaData);

      // Badge
      expect(zpl, contains('^FDCAJAS DE CAMBIO^FS'));

      // Sin ubicación
      expect(zpl, contains('^FDSIN UBICACION^FS'));

      // Footer Caja (Solo NRO INGRESO a la izquierda)
      expect(zpl, contains('^FO40,485^A0N,28,28^FDNRO INGRESO: ING-8821^FS'));
      expect(zpl, isNot(contains('NRO MOTOR:')));
    });

    test('Modelos largos del Registro Civil se truncan a 20 chars para evitar desbordar', () {
      final largoData = EtiquetaData(
        idActivo: 'act-largo-001',
        skuQrFisico: 'MOT-2024-999',
        marca: 'Hyundai',
        modelo: 'SANTA FE GLS 4X4 2.7 AUT',
        anio: 2012,
        cilindrada: '2.7L',
        combustible: 'Bencina',
        transmision: 'Automatica',
        traccion: '4x4',
        numeroMotor: 'G6BA-9922',
        numeroIngreso: 'ING-9900',
        galpon: 'G2',
        pasillo: 'P01',
        pallet: 'PAL-02',
      );

      final zpl = ZplBuilder.buildEtiquetaActivo(largoData);

      // El modelo se recorta a 20 chars: "SANTA FE GLS 4X4 2.7"
      expect(zpl, contains('^FO385,164^A0N,25,25^FDMODELO: SANTA FE GLS 4X4 2.7^FS'));
      // No debe contener el sobrante que causaría desborde fuera del marco
      expect(zpl, isNot(contains('AUT^FS')));
    });
  });

  group('EtiquetaData.fromMap - Deserialización y compatibilidad de payloads', () {
    test('Mapea correctamente payload plano retornado por guardar-paletizado para Caja de Cambios', () {
      final rawBackend = {
        "status": "success",
        "id_activo": "550e8400-e29b-41d4-a716-446655440000",
        "sku_qr_fisico": "CAJ-8801",
        "qr_impreso": false,
        "numero_ingreso": "8801",
        "marca": "Toyota",
        "modelo": "Hilux",
        "anio": 2022,
        "traccion": "4x4",
        "galpon": "G1",
        "pasillo": "P-01",
        "pallet": "PAL-10",
        "cilindrada": "2.8L",
        "combustible": "Diesel",
        "transmision": "Manual 6V",
        "numero_motor": null,
      };

      final etiqueta = EtiquetaData.fromMap(rawBackend);

      expect(etiqueta.idActivo, '550e8400-e29b-41d4-a716-446655440000');
      expect(etiqueta.skuQrFisico, 'CAJ-8801');
      expect(etiqueta.numeroIngreso, '8801');
      expect(etiqueta.marca, 'Toyota');
      expect(etiqueta.modelo, 'Hilux');
      expect(etiqueta.anio, 2022);
      expect(etiqueta.traccion, '4x4');
      expect(etiqueta.cilindrada, '2.8L');
      expect(etiqueta.combustible, 'Diesel');
      expect(etiqueta.transmision, 'Manual 6V');
      expect(etiqueta.numeroMotor, isNull);
      expect(etiqueta.galpon, 'G1');
      expect(etiqueta.pasillo, 'P-01');
      expect(etiqueta.pallet, 'PAL-10');

      // Comprobar que ZPL generado para esta caja incluye las 7 especificaciones sin N/A
      final zpl = ZplBuilder.buildEtiquetaActivo(etiqueta);
      expect(zpl, contains('^FO385,256^A0N,25,25^FDCILINDRADA: 2.8L^FS'));
      expect(zpl, contains('^FO385,302^A0N,25,25^FDCOMBUSTIBLE: DIESEL^FS'));
      expect(zpl, contains('^FO385,348^A0N,25,25^FDTRANSMISION: MANUAL 6V^FS'));
      expect(zpl, contains('^FO385,394^A0N,25,25^FDTRACCION: 4X4^FS'));
      expect(zpl, contains('^FDCAJAS DE CAMBIO^FS'));
      expect(zpl, isNot(contains('NRO MOTOR:')));
    });

    test('Mapea correctamente payload de tareas-pendientes de bodega', () {
      final rawBodega = {
        "id_activo": "550e8400-e29b-41d4-a716-446655440001",
        "numero_ingreso": "8801",
        "marca": "Toyota",
        "modelo": "Hilux",
        "anio": 2022,
        "traccion": "4x4",
        "cilindrada": "2.8L",
        "combustible": "Diesel",
        "transmision": "Manual 6V",
        "numero_motor": null,
        "galpon": "G1",
        "pasillo": "P-01",
        "pallet": "PAL-10",
        "sku_qr_fisico": "CAJ-8801",
      };

      final etiqueta = EtiquetaData.fromMap(rawBodega);

      expect(etiqueta.cilindrada, '2.8L');
      expect(etiqueta.combustible, 'Diesel');
      expect(etiqueta.traccion, '4x4');
      expect(etiqueta.transmision, 'Manual 6V');
      expect(etiqueta.numeroMotor, isNull);
    });
  });
}
