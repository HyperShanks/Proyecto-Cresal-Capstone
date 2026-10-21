import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/recepcion/utils/vehiculo_parser_util.dart';

void main() {
  group('VehiculoParserUtil - Pruebas con data real de Los Pinos (Cresal)', () {
    test('NEW L200 DAKAR DCAB 4X4 2.4 infiere 2.4, Mecánica, Diésel, 4x4 Conectable', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'NEW L200 DAKAR DCAB 4X4 2.4',
        marca: 'MITSUBISHI',
      );
      expect(res.cilindrada, '2.4');
      expect(res.transmision, 'Mecánica');
      expect(res.combustible, 'Diésel');
      expect(res.traccion, '4x4 Conectable (4WD)');
    });

    test('OUTLANDER 4X4 2.4 AUT infiere 2.4, Automática, 4x4 Conectable', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'OUTLANDER 4X4 2.4 AUT',
        marca: 'MITSUBISHI',
      );
      expect(res.cilindrada, '2.4');
      expect(res.transmision, 'Automática');
      expect(res.traccion, '4x4 Conectable (4WD)');
    });

    test('DMAX TH 4WD 3.0 infiere 3.0, 4x4 Conectable, Diésel', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'DMAX TH 4WD 3.0',
        marca: 'CHEVROLET',
      );
      expect(res.cilindrada, '3.0');
      expect(res.combustible, 'Diésel');
      expect(res.traccion, '4x4 Conectable (4WD)');
    });

    test('PARTNER HDI 1.6 infiere 1.6, Diésel, 4x2 Delantera', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'PARTNER HDI 1.6',
        marca: 'PEUGEOT',
      );
      expect(res.cilindrada, '1.6');
      expect(res.combustible, 'Diésel');
      expect(res.traccion, '4x2 Delantera');
      expect(res.transmision, 'Mecánica');
    });

    test('GOL 1.6I infiere 1.6, Gasolina, 4x2 Delantera', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'GOL 1.6I',
        marca: 'VOLKSWAGEN',
      );
      expect(res.cilindrada, '1.6');
      expect(res.combustible, 'Gasolina');
      expect(res.traccion, '4x2 Delantera');
    });

    test('SUBARU IMPREZA 2.0 infiere AWD', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'IMPREZA 2.0',
        marca: 'SUBARU',
      );
      expect(res.cilindrada, '2.0');
      expect(res.traccion, '4x4 Permanente (AWD)');
    });

    test('ACTYON 2.0 AT infiere Automática, Diésel, 2.0', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'ACTYON 2.0 AT',
        marca: 'SSANGYONG',
      );
      expect(res.cilindrada, '2.0');
      expect(res.transmision, 'Automática');
      expect(res.combustible, 'Diésel');
    });

    test('HILUX 2.8 4X2 infiere 4x2 Trasera y Diésel', () {
      final res = VehiculoParserUtil.inferir(
        modelo: 'HILUX 2.8 4X2',
        marca: 'TOYOTA',
      );
      expect(res.cilindrada, '2.8');
      expect(res.combustible, 'Diésel');
      expect(res.traccion, '4x2 Trasera');
    });

    test('Formato centímetros cúbicos (1600cc) infiere 1.6', () {
      final cc = VehiculoParserUtil.extraerCilindrada('CORSA 1600cc');
      expect(cc, '1.6');
    });

    test('Formato con coma decimal (2,4) infiere 2.4', () {
      final cc = VehiculoParserUtil.extraerCilindrada('SORENTO 2,4');
      expect(cc, '2.4');
    });
  });
}
