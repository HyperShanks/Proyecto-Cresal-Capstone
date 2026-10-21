import os
import logging
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
import httpx
from sqlalchemy.orm import Session

from core.config import settings
from database import SessionLocal
from models import Notificacion_Sistema, Orden_Venta, Usuario

logger = logging.getLogger("telegram_service")

try:
    from zoneinfo import ZoneInfo
    TZ_CHILE = ZoneInfo("America/Santiago")
except Exception:
    TZ_CHILE = timezone.utc


class TelegramService:
    @staticmethod
    def _obtener_fecha_chile_formateada() -> str:
        try:
            return datetime.now(TZ_CHILE).strftime("%d/%m/%Y %H:%M")
        except Exception:
            return datetime.now().strftime("%d/%m/%Y %H:%M")

    @staticmethod
    def enviar_mensaje(
        mensaje: str,
        tipo_evento: str,
        referencia_id: str,
        chat_id: Optional[str] = None,
        db: Optional[Session] = None,
    ) -> bool:
        """
        Envía un mensaje formateado a Telegram y asienta la bitácora en Notificacion_Sistema.
        No bloquea ni propaga excepciones al flujo transaccional principal.
        """
        token = settings.TELEGRAM_BOT_TOKEN or os.getenv("TELEGRAM_BOT_TOKEN", "")
        destinatario = chat_id or settings.TELEGRAM_GERENCIA_CHAT_ID or os.getenv("TELEGRAM_GERENCIA_CHAT_ID", "")
        enabled = settings.TELEGRAM_ENABLED and bool(token) and bool(destinatario)

        # Usar sesión propia si no se proveyó una abierta
        cerrar_sesion_al_terminar = False
        if db is None:
            db = SessionLocal()
            cerrar_sesion_al_terminar = True

        notif = Notificacion_Sistema(
            canal="TELEGRAM",
            destinatario=destinatario or "NO_CONFIGURADO",
            tipo_evento=tipo_evento,
            referencia_id=str(referencia_id),
            mensaje=mensaje,
            estado="PENDIENTE",
            intentos=0,
            fecha_creacion=datetime.now(timezone.utc),
        )

        try:
            db.add(notif)
            db.commit()
            db.refresh(notif)

            if not enabled:
                notif.estado = "OMITIDO"
                notif.ultimo_error = "Telegram no configurado o deshabilitado (TELEGRAM_BOT_TOKEN / CHAT_ID vacío)"
                db.commit()
                return False

            url = f"https://api.telegram.org/bot{token}/sendMessage"
            payload = {
                "chat_id": destinatario,
                "text": mensaje,
                "parse_mode": "Markdown",
            }

            with httpx.Client(timeout=4.0) as client:
                res = client.post(url, json=payload)
                notif.intentos += 1

                if res.status_code == 200 and res.json().get("ok", False):
                    notif.estado = "ENVIADO"
                    notif.fecha_envio = datetime.now(timezone.utc)
                    db.commit()
                    return True
                else:
                    notif.estado = "FALLIDO"
                    notif.ultimo_error = f"HTTP {res.status_code}: {res.text[:500]}"
                    db.commit()
                    return False

        except Exception as e:
            logger.error(f"[TELEGRAM] Error al enviar mensaje: {e}")
            try:
                notif.estado = "FALLIDO"
                notif.intentos += 1
                notif.ultimo_error = str(e)[:500]
                db.commit()
            except Exception:
                db.rollback()
            return False
        finally:
            if cerrar_sesion_al_terminar:
                db.close()

    # =========================================================================
    # PLANTILLAS DISPARADORES PARA GERENCIA
    # =========================================================================

    @classmethod
    def notificar_venta_pagada(
        cls,
        folio: str,
        cliente_nombre: str,
        rut_cliente: str,
        vendedor_nombre: str,
        cajero_nombre: str,
        total_venta: int,
        medio_pago: str,
        cantidad_items_inventariados: int,
    ) -> bool:
        """Disparador 1.A: Venta Regular Pagada al 100% (Solo con Repuestos Inventariados)."""
        fecha_hora = cls._obtener_fecha_chile_formateada()
        monto_fmt = f"{total_venta:,}".replace(",", ".")

        mensaje = (
            f"💰 *VENTA PAGADA EN CAJA (INVENTARIADO)*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📋 *Orden:* `{folio}`\n"
            f"👤 *Cliente:* {cliente_nombre} ({rut_cliente})\n"
            f"💼 *Vendedor:* {vendedor_nombre}\n"
            f"🏦 *Cajero(a):* {cajero_nombre}\n"
            f"💵 *Monto Total:* ${monto_fmt}\n"
            f"💳 *Medio de Pago:* {medio_pago}\n"
            f"📦 *Repuestos Inventariados:* {cantidad_items_inventariados} pieza(s)\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⏱️ _{fecha_hora}_"
        )
        return cls.enviar_mensaje(
            mensaje=mensaje,
            tipo_evento="VENTA_PAGADA",
            referencia_id=folio,
        )

    @classmethod
    def notificar_venta_en_verde_pagada(
        cls,
        folio: str,
        cliente_nombre: str,
        rut_cliente: str,
        telefono_contacto: str,
        categoria_requerida: str,
        marca_modelo: str,
        vendedor_nombre: str,
        cajero_nombre: str,
        monto_pagado: int,
        medio_pago: str,
    ) -> bool:
        """Disparador 1.B: Venta en Verde Pagada al 100% (Reserva Backorder)."""
        fecha_hora = cls._obtener_fecha_chile_formateada()
        monto_fmt = f"{monto_pagado:,}".replace(",", ".")

        mensaje = (
            f"🌱 *NUEVA VENTA EN VERDE PAGADA (RESERVA)*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📋 *Orden:* `{folio}`\n"
            f"👤 *Cliente:* {cliente_nombre} ({rut_cliente})\n"
            f"📞 *Teléfono:* {telefono_contacto or 'Sin teléfono'}\n"
            f"🚗 *Vehículo / Pieza:* {categoria_requerida} - {marca_modelo}\n"
            f"💼 *Vendedor:* {vendedor_nombre}\n"
            f"🏦 *Cajero(a):* {cajero_nombre}\n"
            f"💵 *Monto Pagado:* ${monto_fmt}\n"
            f"💳 *Medio de Pago:* {medio_pago}\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚠️ *Compromiso:* Pendiente de asignación física de repuesto en patio/bodega\n"
            f"⏱️ _{fecha_hora}_"
        )
        return cls.enviar_mensaje(
            mensaje=mensaje,
            tipo_evento="VENTA_EN_VERDE_PAGADA",
            referencia_id=folio,
        )

    @classmethod
    def notificar_entrega_barrera(
        cls,
        folio: str,
        cliente_nombre: str,
        descripcion_pieza: str,
        sku: str,
        bodeguero_nombre: str,
        sucursal_nombre: str,
    ) -> bool:
        """Disparador 2: Entrega Física en Barrera de Salida (Bodega PDA / Dual-Scan)."""
        fecha_hora = cls._obtener_fecha_chile_formateada()

        mensaje = (
            f"🚚 *REPUESTO ENTREGADO EN BARRERA DE SALIDA*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📋 *Orden:* `{folio}`\n"
            f"👤 *Cliente:* {cliente_nombre}\n"
            f"📦 *Repuesto:* {descripcion_pieza}\n"
            f"🏷️ *SKU:* `{sku}`\n"
            f"👷 *Validado en Barrera por:* {bodeguero_nombre}\n"
            f"🏢 *Sucursal:* {sucursal_nombre}\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⏱️ _{fecha_hora}_"
        )
        return cls.enviar_mensaje(
            mensaje=mensaje,
            tipo_evento="DESPACHO_ENTREGA",
            referencia_id=folio,
        )

    @classmethod
    def notificar_orden_anulada(
        cls,
        folio: str,
        total_venta: int,
        usuario_nombre: str,
        rol_nombre: str,
        motivo_anulacion: str,
        observacion_anulacion: str,
        cantidad_items_liberados: int,
    ) -> bool:
        """Disparador 3: Anulación de Orden de Venta (Alerta Auditoría)."""
        fecha_hora = cls._obtener_fecha_chile_formateada()
        monto_fmt = f"{total_venta:,}".replace(",", ".")

        mensaje = (
            f"⚠️ *ALERTA: ORDEN DE VENTA ANULADA*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📋 *Orden:* `{folio}`\n"
            f"💵 *Monto Anulado:* ${monto_fmt}\n"
            f"👤 *Usuario Responsable:* {usuario_nombre} ({rol_nombre})\n"
            f"🎯 *Motivo:* *{motivo_anulacion}*\n"
            f"📝 *Observación:*\n_{observacion_anulacion}_\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🔄 *Stock:* {cantidad_items_liberados} repuesto(s) liberados a inventario\n"
            f"⏱️ _{fecha_hora}_"
        )
        return cls.enviar_mensaje(
            mensaje=mensaje,
            tipo_evento="ORDEN_ANULADA",
            referencia_id=folio,
        )

    @classmethod
    def notificar_repuesto_despaletizado(
        cls,
        sku: str,
        pieza_nombre: str,
        ubicacion_anterior: str,
        bodeguero_nombre: str,
        motivo_despaletizado: str,
        observacion_despaletizado: str,
    ) -> bool:
        """Disparador 4: Despaletizado de Repuesto (Alerta Inventario WMS)."""
        fecha_hora = cls._obtener_fecha_chile_formateada()

        mensaje = (
            f"🚨 *ALERTA: REPUESTO DESPALETIZADO*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🏷️ *SKU:* `{sku}`\n"
            f"📦 *Pieza:* {pieza_nombre}\n"
            f"📍 *Ubicación Previa:* {ubicacion_anterior}\n"
            f"👷 *Operario:* {bodeguero_nombre}\n"
            f"🎯 *Motivo:* *{motivo_despaletizado}*\n"
            f"📝 *Justificación:*\n_{observacion_despaletizado}_\n"
            f"━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚠️ *Estado Actual:* En Desarme (Sin ubicación fija)\n"
            f"⏱️ _{fecha_hora}_"
        )
        return cls.enviar_mensaje(
            mensaje=mensaje,
            tipo_evento="REPUESTO_DESPALETIZADO",
            referencia_id=sku,
        )
