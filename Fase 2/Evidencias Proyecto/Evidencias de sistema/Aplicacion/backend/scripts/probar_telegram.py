"""
Script de verificación y diagnóstico de Notificaciones Telegram para Gerencia.
Uso:
    python backend/scripts/probar_telegram.py
"""
import sys
import os
from pathlib import Path

# Agregar raíz de backend al PYTHONPATH
_BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_BACKEND_DIR))

# Asegurar encoding UTF-8 en consola Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from core.config import settings
from database import SessionLocal
from services.telegram_service import TelegramService
from models import Notificacion_Sistema


def main():
    print("=" * 60)
    print("🤖 DIAGNÓSTICO DE NOTIFICACIONES TELEGRAM (GERENCIA)")
    print("=" * 60)

    token = settings.TELEGRAM_BOT_TOKEN
    chat_id = settings.TELEGRAM_GERENCIA_CHAT_ID
    enabled = settings.TELEGRAM_ENABLED

    print(f"• TELEGRAM_ENABLED:           {enabled}")
    print(f"• TELEGRAM_BOT_TOKEN:         {token[:6]}...{token[-4:] if len(token) > 10 else 'NO CONFIGURADO'}")
    print(f"• TELEGRAM_GERENCIA_CHAT_ID:  {chat_id or 'NO CONFIGURADO'}")
    print("-" * 60)

    if not token or not chat_id:
        print("⚠️ AVISO: Faltan credenciales en backend/.env.")
        print("Para enviar mensajes reales, añade al archivo backend/.env:")
        print('  TELEGRAM_BOT_TOKEN="123456789:ABCdef..."')
        print('  TELEGRAM_GERENCIA_CHAT_ID="-1001234567890"  # o tu ID personal')
        print('  TELEGRAM_ENABLED="true"\n')
        print("Aún así, ejecutaremos la llamada para comprobar que se guarde en la BD 'Notificacion_Sistema'...")

    mensaje_prueba = (
        "🧪 *PRUEBA DE INTEGRACIÓN TELEGRAM*\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "Sistema de Auditoría Cresal Repuestos\n"
        "Estado: Conexión con Bot de Gerencia establecida.\n"
        "━━━━━━━━━━━━━━━━━━━━━━\n"
        "⏱️ _Prueba operativa exitosa_"
    )

    db = SessionLocal()
    try:
        print("\n🚀 Enviando mensaje de prueba mediante TelegramService...")
        exito = TelegramService.enviar_mensaje(
            mensaje=mensaje_prueba,
            tipo_evento="PRUEBA_SISTEMA",
            referencia_id="TEST-001",
            db=db,
        )

        # Consultar último registro en Notificacion_Sistema
        ultimo_registro = (
            db.query(Notificacion_Sistema)
            .order_by(Notificacion_Sistema.id_notificacion.desc())
            .first()
        )

        print("\n📊 RESULTADO EN BASE DE DATOS (Notificacion_Sistema):")
        if ultimo_registro:
            print(f"• ID Notificación:  {ultimo_registro.id_notificacion}")
            print(f"• Tipo Evento:      {ultimo_registro.tipo_evento}")
            print(f"• Destinatario:     {ultimo_registro.destinatario}")
            print(f"• Estado:           {ultimo_registro.estado}")
            print(f"• Intentos:         {ultimo_registro.intentos}")
            print(f"• Fecha Creación:   {ultimo_registro.fecha_creacion}")
            print(f"• Fecha Envío:      {ultimo_registro.fecha_envio}")
            if ultimo_registro.ultimo_error:
                print(f"• Detalle / Error:  {ultimo_registro.ultimo_error}")
        else:
            print("⚠️ No se encontró registro en Notificacion_Sistema.")

        if exito:
            print("\n🎉 ¡MENSAJE ENVIADO A TELEGRAM EXITOSAMENTE!")
        else:
            print("\nℹ️ El mensaje no se envió a la API de Telegram (revisa las credenciales o estado arriba).")
            print("El sistema manejó el fallo de forma resiliente sin errores 500.")

    finally:
        db.close()
    print("=" * 60)


if __name__ == "__main__":
    main()
