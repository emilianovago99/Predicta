import unittest
from unittest.mock import MagicMock, patch
import mysql.connector
from pydantic import ValidationError
import main


class LogicTests(unittest.TestCase):
    def setUp(self):
        self.limits = {f'{prefix}_{level}': value for prefix in
                       ('temp', 'temp_amb', 'vib', 'volt', 'vel', 'hum')
                       for level, value in [('alerta', 50), ('peligro', 80)]}
        self.row = dict(temperatura=25, temp_ambiente=22, vibracion=2,
                        voltaje=12, velocidad=20, humedad=30)

    def test_disabled_sensor_does_not_raise_alarm(self):
        self.row['temperatura'] = 100
        self.assertEqual(main._etiqueta_estado(self.row, self.limits), 'peligro')
        self.limits['medir_temp'] = False
        self.assertEqual(main._etiqueta_estado(self.row, self.limits), 'optimo')

    def test_boundary_is_inclusive(self):
        self.row['humedad'] = 50
        self.assertEqual(main._etiqueta_estado(self.row, self.limits), 'alerta')
        self.row['humedad'] = 80
        self.assertEqual(main._etiqueta_estado(self.row, self.limits), 'peligro')

    def test_telemetry_rejects_invalid_values_and_supports_firmware_alias(self):
        payload = dict(self.row, id_maquina='M-01')
        self.assertEqual(main.Telemetria(**payload).maquina_id, 'M-01')
        for field, value in [('humedad', 101), ('temperatura', float('nan')), ('velocidad', -1)]:
            with self.subTest(field=field), self.assertRaises(ValidationError):
                main.Telemetria(**{**payload, field: value})

    def test_no_prediction_from_disabled_channels(self):
        history = [{**self.row, 'temperatura': 20 + n * 2, 'vibracion': n} for n in range(20)]
        self.limits.update({f'medir_{p}': False for p in ('temp', 'temp_amb', 'vib', 'volt', 'vel', 'hum')})
        result = main.calcular_prediccion_mantenimiento('TEST', history, self.limits)
        self.assertFalse(result['requiere_alerta_preventiva'])
        self.assertEqual(result['rul_ciclos'], -1)

    def test_password_hash_and_plaintext_rejection(self):
        hashed = main.hash_password('test-password')
        self.assertNotIn('test-password', hashed)
        self.assertTrue(main.verify_password('test-password', hashed))
        self.assertFalse(main.verify_password('wrong', hashed))
        self.assertFalse(main.verify_password('legacy', 'legacy'))

    def test_company_rolls_back_when_email_exists(self):
        db = MagicMock()
        cursor = db.cursor.return_value
        cursor.execute.side_effect = [None, mysql.connector.IntegrityError()]
        data = main.EmpresaRegistro(nombre='Acme', responsable='Alex', email='a@example.com', password='test-password')
        with patch.object(main, 'conectar_db', return_value=db):
            with self.assertRaises(main.HTTPException) as error:
                main.registrar_empresa(data)
        self.assertEqual(error.exception.status_code, 409)
        db.rollback.assert_called_once()
        db.commit.assert_not_called()
        db.close.assert_called_once()

    def test_unknown_machine_returns_404(self):
        db = MagicMock()
        db.cursor.return_value.fetchone.return_value = None
        with patch.object(main, 'conectar_db', return_value=db):
            with self.assertRaises(main.HTTPException) as error:
                main.registrar_telemetria(main.Telemetria(maquina_id='MISSING', **self.row), {'id_maquina': 'MISSING'})
        self.assertEqual(error.exception.status_code, 404)


if __name__ == '__main__':
    unittest.main()
