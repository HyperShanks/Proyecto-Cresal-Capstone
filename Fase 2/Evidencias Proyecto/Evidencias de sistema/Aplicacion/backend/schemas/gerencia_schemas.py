# backend/schemas/gerencia_schemas.py
"""
Esquemas Pydantic V2 para el módulo de Gerencia y Dashboard Ejecutivo (HU-5.1).
Defino los DTOs analíticos para métricas, pagos y flujo operativo.
"""

from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


class KpiFinancieroDTO(BaseModel):
    """
    DTO para las 4 métricas financieras superiores del Dashboard Ejecutivo.
    Diseñé este esquema para transferir la facturación diaria, transacciones,
    acumulado mensual MTD y ticket promedio calculado.
    """
    ventas_del_dia: int = Field(
        description="Suma total de pagos liquidados hoy en CLP"
    )
    transacciones_hoy: int = Field(
        description="Cantidad de órdenes pagadas durante el día de hoy"
    )
    acumulado_mensual_mtd: int = Field(
        description="Suma acumulada de facturación del mes actual"
    )
    ticket_promedio: float = Field(
        description="Monto promedio recaudado por transacción de venta"
    )
    margen_bruto: Optional[float] = Field(
        default=64.8,
        description="Porcentaje estimado de margen bruto"
    )

    model_config = ConfigDict(from_attributes=True)


class DesglosePagoDTO(BaseModel):
    """
    DTO que representa la recaudación individual por cada método de pago.
    Lo programé para alimentar la leyenda y segmentos del gráfico de dona,
    permitiendo alternar entre métrica monetaria ($) y volumen de transacciones (#).
    """
    metodo_pago: str = Field(
        description="Método: Efectivo, Débito, Crédito, etc."
    )
    monto_total: int = Field(
        description="Monto total recaudado en CLP por este método"
    )
    porcentaje: float = Field(
        description="Porcentaje respecto al total monetario recaudado hoy"
    )
    cantidad: int = Field(
        default=1,
        description="Cantidad de pagos procesados por este método"
    )
    porcentaje_cantidad: float = Field(
        default=0.0,
        description="Porcentaje respecto al total de transacciones de pago de hoy"
    )

    model_config = ConfigDict(from_attributes=True)


class ResumenPagosDTO(BaseModel):
    """
    DTO consolidado para el gráfico y desglose de recaudación.
    Permite contrastar arqueo físico frente a canales electrónicos y total transacciones.
    """
    efectivo_fisico: int = Field(
        description="Total recaudado en efectivo físico en caja"
    )
    canales_electronicos: int = Field(
        description="Total en canales electrónicos (Tarjetas, Transferencias)"
    )
    total_transacciones: int = Field(
        default=0,
        description="Total de pagos individuales registrados hoy"
    )
    desglose: List[DesglosePagoDTO] = Field(
        default_factory=list,
        description="Lista detallada por medio de pago"
    )

    model_config = ConfigDict(from_attributes=True)


class FlujoOperativoDTO(BaseModel):
    """
    DTO con el pulso operativo de bodega y alertas ejecutivas.
    Programé estos contadores para el Bento de logística y riesgo.
    """
    en_preparacion: int = Field(
        description="Ítems en proceso de bajada de rack o preparación física"
    )
    listos_mostrador: int = Field(
        description="Piezas preparadas esperando retiro de cliente en mesón"
    )
    enviados_courier: int = Field(
        description="Órdenes despachadas en tránsito con courier"
    )
    alertas_saldo_pendiente: int = Field(
        description="Órdenes con saldo retenido o pendiente de pago"
    )
    cuellos_botella_paletizados: int = Field(
        description="Repuestos paletizados sin precio comercial asignado"
    )

    model_config = ConfigDict(from_attributes=True)


# ==========================================
# DTOs PARA SUPERVISIÓN DE BACKORDERS (HU-5.4)
# ==========================================

class BackorderGerenciaItemDTO(BaseModel):
    """
    DTO que representa una reserva de compra por encargo (Backorder / compra en verde)
    para el visor maestro de supervisión de gerencia (HU-5.4).
    """
    id_reserva: str = Field(description="UUID de la reserva")
    folio: str = Field(description="Folio amigable (ej. RES-5401)")
    fecha_creacion: str = Field(description="Fecha formateada o relativa")
    fecha_creacion_iso: str = Field(description="Fecha ISO completa en UTC")
    id_cliente: str = Field(description="UUID del cliente")
    cliente_nombre: str = Field(description="Nombre completo del cliente CRM")
    cliente_telefono: Optional[str] = Field(default=None, description="Teléfono del cliente")
    cliente_rut: Optional[str] = Field(default=None, description="RUT del cliente")
    id_vendedor: str = Field(description="UUID del vendedor")
    vendedor_nombre: str = Field(description="Nombre del vendedor")
    id_sucursal: int = Field(description="ID de la sucursal de registro")
    sucursal_nombre: str = Field(description="Nombre de la sucursal")
    id_categoria_requerida: int = Field(description="ID de la categoría requerida")
    categoria_nombre: str = Field(description="Nombre de la categoría requerida (Motor, Caja, etc.)")
    marca_requerida: str = Field(description="Marca solicitada")
    modelo_requerido: str = Field(description="Modelo solicitado")
    anio_requerido: Optional[int] = Field(default=None, description="Año solicitado")
    cilindrada_requerida: Optional[str] = Field(default=None, description="Cilindrada")
    combustible_requerido: Optional[str] = Field(default=None, description="Combustible")
    transmision_requerida: Optional[str] = Field(default=None, description="Transmisión")
    notas_preparacion: Optional[str] = Field(default=None, description="Notas técnicas o de tránsito")
    precio_acordado: int = Field(description="Precio comercial pactado con el cliente en CLP")
    descuento: int = Field(default=0, description="Descuento comercial aplicado a la orden en CLP")
    monto_abonado: int = Field(description="Seña recaudada en caja en CLP")
    saldo_pendiente: int = Field(description="Saldo por pagar")
    estado_reserva: str = Field(description="Pendiente, Confirmada, Completada, Anulada")
    id_activo_asignado: Optional[str] = Field(default=None, description="UUID del repuesto donante asignado")
    activo_asignado_sku: Optional[str] = Field(default=None, description="SKU QR físico del repuesto asignado")
    id_orden: Optional[str] = Field(default=None, description="UUID de la orden de venta final generada")

    model_config = ConfigDict(from_attributes=True)


class BackorderGerenciaListResponse(BaseModel):
    """Respuesta paginada del visor maestro de backorders."""
    items: List[BackorderGerenciaItemDTO] = Field(default_factory=list)
    total_count: int = Field(description="Total de encargos registrados que coinciden con filtros")
    total_recaudado_senas: int = Field(description="Total de dinero recaudado en señas de los encargos filtrados")

    model_config = ConfigDict(from_attributes=True)


class BackorderGerenciaKpisDTO(BaseModel):
    """Cabecera de 3 tarjetas de resumen ejecutivo de backorders."""
    total_activos: int = Field(description="Total backorders activos en estado Pendiente o Confirmada")
    capital_retenido: int = Field(description="Suma total de montos abonados como seña en reservas activas")
    listos_para_liquidar: int = Field(description="Backorders activos que ya cuentan con un repuesto físico asignado (match)")
    total_registrados: int = Field(default=0, description="Total histórico de encargos")
    total_recaudado_senas: int = Field(default=0, description="Total histórico de señas recaudadas")

    model_config = ConfigDict(from_attributes=True)


class SucursalGerenciaDTO(BaseModel):
    """DTO para listado de sucursales activas en módulo de Gerencia."""
    id_sucursal: int = Field(description="ID único de la sucursal en base de datos")
    nombre_sucursal: str = Field(description="Nombre oficial de la sucursal")
    es_casa_matriz: bool = Field(default=False, description="Indica si corresponde a la Casa Matriz de Cresal")

    model_config = ConfigDict(from_attributes=True)
