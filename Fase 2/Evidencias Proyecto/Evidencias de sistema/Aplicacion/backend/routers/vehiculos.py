import asyncio
import uuid
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy.orm import Session
from database import SessionLocal, get_db
import schemas
from services.vehiculo_service import procesar_patente_y_guardar
from sqlalchemy import func, cast, Integer, or_
from models import Vehiculo_Origen, Activo_Inventariado, Detalle_Motor, Detalle_Caja_Cambio, Estado_Activo
from google.cloud import vision
import json # <-- Importante para traducir el texto a JSON
import models
from dotenv import load_dotenv # Para cargar el .env
from typing import List, Optional # Para definir la lista de imágenes en FastAPI
from datetime import datetime, date
from core.security import get_current_user, require_recepcion_or_admin, get_optional_user
from core.storage import supabase
import re

# Instanciamos el enrutador con su prefijo oficial (Sub-tarea A)
router = APIRouter(
    prefix="/api/v1/vehiculos",
    tags=["Autocompletado de Vehículos"]
)

# ==========================================
# 0. RUTAS DE RECEPCIÓN VEHICULAR DE PATIO (SPEC-22)
# ==========================================

@router.get("/recepcion/siguiente-ingreso", status_code=200)
def obtener_siguiente_ingreso_recepcion(
    db: Session = Depends(get_db),
    usuario_logeado: Optional[models.Usuario] = Depends(get_optional_user)
):
    """
    Retorna el siguiente número correlativo para la recepción vehicular en patio.
    Accesible para roles: Recepción (9), Bodeguero (1), Gerencia (4) y Administrador (5).
    """
    resultado = db.query(func.max(cast(Vehiculo_Origen.numero_ingreso, Integer))).scalar()
    siguiente = 1 if resultado is None else resultado + 1
    return {"siguiente_ingreso": str(siguiente)}



@router.get("/recepcion/recientes", response_model=schemas.VehiculoRecepcionRecientesResponse, status_code=200)
def listar_ingresos_recientes(
    limite: int = 50,
    busqueda: Optional[str] = None,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(require_recepcion_or_admin)
):
    """
    Lista los vehículos recientemente ingresados con soporte de búsqueda
    para evitar duplicados antes de descargar el vehículo de la grúa.
    """
    query = db.query(Vehiculo_Origen)
    if busqueda and busqueda.strip():
        termino = f"%{busqueda.strip().upper()}%"
        query = query.filter(
            or_(
                Vehiculo_Origen.patente.ilike(termino),
                Vehiculo_Origen.numero_ingreso.ilike(termino),
                Vehiculo_Origen.marca.ilike(termino),
                Vehiculo_Origen.modelo.ilike(termino),
                Vehiculo_Origen.grua.ilike(termino),
                Vehiculo_Origen.factura.ilike(termino)
            )
        )
    total = query.count()
    vehiculos = query.order_by(
        cast(Vehiculo_Origen.numero_ingreso, Integer).desc()
    ).limit(limite).all()
    return schemas.VehiculoRecepcionRecientesResponse(
        total=total,
        items=vehiculos
    )


@router.post("/recepcion/registro", response_model=schemas.VehiculoRecepcionItem, status_code=201)
def registrar_ingreso_vehicular(
    payload: schemas.VehiculoRecepcionCreate,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(require_recepcion_or_admin)
):
    """
    Registra un vehículo donante en patio según la Matriz de 13 Columnas (A-M).
    Permite ingreso con patente o S/PPU automático (SPPU-{numero_ingreso}).
    Crea los activos base pendientes de desarme para integración con bodega.
    """
    # 1. Asignación / Validación de correlativo de ingreso
    if not payload.numero_ingreso or not str(payload.numero_ingreso).strip():
        resultado = db.query(func.max(cast(Vehiculo_Origen.numero_ingreso, Integer))).scalar()
        num_ingreso = str(1 if resultado is None else resultado + 1)
    else:
        num_ingreso = str(payload.numero_ingreso).strip()

    # Validar que el número de ingreso no esté duplicado
    existe_num = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.numero_ingreso == num_ingreso).first()
    if existe_num:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El número de ingreso N° {num_ingreso} ya se encuentra registrado (Vehículo: {existe_num.marca} {existe_num.modelo} - {existe_num.patente})."
        )

    # 2. Asignación de Patente o clave S/PPU
    patente_raw = (payload.patente or "").strip().upper()
    if payload.es_sppu or not patente_raw or patente_raw in ["S/PPU", "SPPU", "S/P", "SIN PATENTE", "S/PATENTE"]:
        patente_final = f"SPPU-{num_ingreso}"
    else:
        patente_final = patente_raw
        # Verificar duplicidad de patente
        existe_pat = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.patente == patente_final).first()
        if existe_pat:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"La patente '{patente_final}' ya existe en el sistema asociada al ingreso N° {existe_pat.numero_ingreso}."
            )

    # 3. Fecha de ingreso
    if payload.fecha_ingreso and payload.fecha_ingreso.strip():
        try:
            fecha_ingreso_dt = datetime.strptime(payload.fecha_ingreso.strip(), "%Y-%m-%d").date()
        except ValueError:
            fecha_ingreso_dt = datetime.now().date()
    else:
        fecha_ingreso_dt = datetime.now().date()

    # 4. Instanciar Vehiculo_Origen con las 13 columnas
    id_vehiculo = uuid.uuid4()
    nuevo_vehiculo = Vehiculo_Origen(
        id_vehiculo=id_vehiculo,
        numero_ingreso=num_ingreso,
        patente=patente_final,
        vin=None,
        factura=payload.factura.strip() if payload.factura else None,
        fecha_ingreso=fecha_ingreso_dt,
        origen=payload.origen.strip().upper() if payload.origen else None,
        marca=payload.marca.strip().upper(),
        modelo=payload.modelo.strip().upper(),
        anio=payload.anio,
        color=payload.color.strip().upper() if payload.color else None,
        numero_motor=payload.numero_motor.strip().upper() if payload.numero_motor else None,
        destino=payload.destino.strip().upper() if payload.destino else "DESARME",
        grua=payload.grua.strip().upper() if payload.grua else None,
        observaciones=payload.observaciones.strip() if payload.observaciones else None,
        traccion=payload.traccion.strip() if payload.traccion else None,
        estado="Activo",
        fecha_creacion=datetime.now()
    )
    db.add(nuevo_vehiculo)
    db.flush()

    # 5. Si el destino es DESARME, instanciar los activos base (Motor y Caja) en estado 'En Desarme'
    if nuevo_vehiculo.destino == "DESARME":
        sucursal_id = usuario_logeado.id_sucursal if usuario_logeado.id_sucursal else 1
        estado_desarme = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Desarme").first()
        id_estado_desarme = estado_desarme.id_estado if estado_desarme else 5

        # Motor (Categoría 1)
        id_motor = uuid.uuid4()
        activo_motor = Activo_Inventariado(
            id_activo=id_motor,
            sku_qr_fisico=f"MOT-{num_ingreso}",
            id_categoria=1,
            id_estado=id_estado_desarme,
            id_sucursal_actual=sucursal_id,
            id_vehiculo=id_vehiculo,
            estado="Activo",
            fecha_creacion=datetime.now(),
            qr_impreso=False,
            version_lock=1
        )
        db.add(activo_motor)

        # Detalle Motor
        det_motor = Detalle_Motor(
            id_activo=id_motor,
            cilindrada=payload.cilindrada or "S/A",
            combustible=payload.combustible or "Gasolina",
            transmision_tipo=payload.transmision or "Mecánica"
        )
        db.add(det_motor)

        # Caja de Cambios (Categoría 2)
        id_caja = uuid.uuid4()
        activo_caja = Activo_Inventariado(
            id_activo=id_caja,
            sku_qr_fisico=f"CAJ-{num_ingreso}",
            id_categoria=2,
            id_estado=id_estado_desarme,
            id_sucursal_actual=sucursal_id,
            id_vehiculo=id_vehiculo,
            estado="Activo",
            fecha_creacion=datetime.now(),
            qr_impreso=False,
            version_lock=1
        )
        db.add(activo_caja)

        det_caja = Detalle_Caja_Cambio(
            id_activo=id_caja,
            transmision_tipo=payload.transmision or "Mecánica"
        )
        db.add(det_caja)

    db.commit()
    db.refresh(nuevo_vehiculo)
    return nuevo_vehiculo


@router.get("/recepcion/exportar-matriz", response_model=schemas.VehiculoRecepcionExportarResponse, status_code=200)
def exportar_matriz_vehicular(
    limite: int = 100,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(require_recepcion_or_admin)
):
    """
    Exporta los registros estructurados en las 13 columnas exactas de la Matriz Central
    y provee el texto en formato TSV (Tab-Separated Values) compatible con pegado directo en Excel.
    """
    vehiculos = db.query(Vehiculo_Origen).order_by(
        cast(Vehiculo_Origen.numero_ingreso, Integer).desc()
    ).limit(limite).all()

    # Columnas: A: N° Ingreso, B: Patente, C: Factura, D: Fecha ingreso, E: Origen,
    # F: Marca, G: Modelo, H: Año, I: Color, J: N° Motor, K: Destino, L: GRUA, M: OBSERVACIONES
    encabezados = [
        "N° Ingreso", "Patente", "Factura", "Fecha ingreso", "Origen",
        "Marca", "Modelo", "Año", "Color", "N° Motor", "Destino", "GRUA", "OBSERVACIONES"
    ]
    lineas = ["\t".join(encabezados)]

    for v in vehiculos:
        fila = [
            str(v.numero_ingreso or ""),
            str(v.patente or ""),
            str(v.factura or ""),
            v.fecha_ingreso.strftime("%Y-%m-%d") if v.fecha_ingreso else "",
            str(v.origen or ""),
            str(v.marca or ""),
            str(v.modelo or ""),
            str(v.anio or ""),
            str(v.color or ""),
            str(v.numero_motor or ""),
            str(v.destino or "DESARME"),
            str(v.grua or ""),
            str(v.observaciones or "").replace("\t", " ").replace("\n", " ")
        ]
        lineas.append("\t".join(fila))

    tsv_completo = "\n".join(lineas)
    return schemas.VehiculoRecepcionExportarResponse(
        total=len(vehiculos),
        tsv=tsv_completo,
        items=vehiculos
    )


@router.post("/ocr-padron", status_code=200)
async def procesar_ocr_padron(
    file: UploadFile = File(...),
    usuario_logeado: Optional[models.Usuario] = Depends(get_optional_user)
):
    """
    [SPEC-22] OCR Inteligente para escaneo de Padrón Vehicular (Certificado de Inscripción).
    Extrae automáticamente datos para pre-llenar los 4 pasos del formulario:
    - Patente (Paso 1)
    - Marca, Modelo, Año, N° Motor, Color (Paso 2)
    - Resumen (Paso 4)
    """
    try:
        contenido = await file.read()
        if not contenido:
            raise HTTPException(status_code=400, detail="El archivo de imagen está vacío.")

        client = vision.ImageAnnotatorClient()
        image = vision.Image(content=contenido)
        response = client.text_detection(image=image)

        if response.error.message:
            raise HTTPException(status_code=500, detail=f"Google Vision: {response.error.message}")

        if not response.text_annotations:
            return {
                "exito": False,
                "mensaje": "No se detectó texto en la fotografía.",
                "patente": None,
                "marca": None,
                "modelo": None,
                "anio": None,
                "numero_motor": None,
                "color": None
            }

        texto_crudo = response.text_annotations[0].description
        texto_upper = texto_crudo.upper()

        patente_detectada = None
        marca_detectada = None
        modelo_detectado = None
        anio_detectado = None
        motor_detectado = None
        color_detectado = None

        # 1. Patente Chilena (4 letras + 2 dígitos o 2 letras + 4 dígitos)
        patente_match = re.search(r'\b([A-Z]{4})[\s\.\-]*([0-9]{2})\b', texto_upper)
        if patente_match:
            patente_detectada = f"{patente_match.group(1)}{patente_match.group(2)}"
        else:
            patente_match_antigua = re.search(r'\b([A-Z]{2})[\s\.\-]*([0-9]{4})\b', texto_upper)
            if patente_match_antigua:
                patente_detectada = f"{patente_match_antigua.group(1)}{patente_match_antigua.group(2)}"

        # 2. Marcas automotrices más frecuentes en Chile
        marcas_conocidas = [
            "TOYOTA", "CHEVROLET", "HYUNDAI", "NISSAN", "SUZUKI", "KIA", "PEUGEOT",
            "FORD", "VOLKSWAGEN", "MITSUBISHI", "MAZDA", "RENAULT", "FIAT", "HONDA",
            "JEEP", "CHERY", "MG", "SUBARU", "CITROEN", "DODGE", "BMW", "MERCEDES-BENZ",
            "GREAT WALL", "CHANGAN", "JAC", "HAVAL", "RAM", "AUDI", "VOLVO", "SSANGYONG"
        ]
        for m in marcas_conocidas:
            if re.search(r'\b' + re.escape(m) + r'\b', texto_upper):
                marca_detectada = m
                break

        # 3. Año (1980 - 2029)
        anio_match = re.search(r'(?:A[ÑN]O|FABRICACI[OÓ]N|MODELO)?\s*[:\.]?\s*(20[0-2][0-9]|19[89][0-9])\b', texto_upper)
        if anio_match:
            try:
                anio_detectado = int(anio_match.group(1))
            except (ValueError, TypeError):
                pass

        # 4. Color de carrocería
        colores_conocidos = [
            "BLANCO", "GRIS", "PLATA", "NEGRO", "ROJO", "AZUL", "VERDE",
            "AMARILLO", "BEIGE", "DORADO", "CAFE", "BURDEO", "NARANJA"
        ]
        for c in colores_conocidos:
            if re.search(r'\b' + re.escape(c) + r'\b', texto_upper):
                color_detectado = c
                break

        # 5. Número de Motor
        motor_match = re.search(r'(?:MOTOR|N[°ºRO\.]*\s*MOTOR)\s*[:\.]?\s*([A-Z0-9]{5,22})', texto_upper)
        if motor_match:
            motor_detectado = motor_match.group(1).strip()

        # 6. Modelo del vehículo
        modelo_match = re.search(r'MODELO\s*[:\.]?\s*([A-Z0-9\s\.\-]{2,25})', texto_upper)
        if modelo_match:
            modelo_detectado = modelo_match.group(1).strip()

        return {
            "exito": True,
            "patente": patente_detectada,
            "marca": marca_detectada,
            "modelo": modelo_detectado,
            "anio": anio_detectado,
            "numero_motor": motor_detectado,
            "color": color_detectado,
            "texto_detectado": texto_crudo[:200]
        }
    except Exception as e:
        print(f"⚠️ Error en OCR Padrón: {e}")
        return {
            "exito": False,
            "mensaje": f"No se pudo procesar la imagen: {str(e)}",
            "patente": None,
            "marca": None,
            "modelo": None,
            "anio": None,
            "numero_motor": None,
            "color": None
        }


# ==========================================
# 1. RUTAS ESTÁTICAS (Van primero)
# ==========================================

@router.get("/siguiente-ingreso", status_code=200)
def obtener_siguiente_ingreso(db: Session = Depends(get_db), usuario_logeado: models.Usuario = Depends(get_current_user)):
    """
    Calcula y retorna el siguiente número correlativo para el ingreso de un vehículo.
    """
    # Buscamos el valor máximo, forzando a SQL a tratar el varchar como un Integer
    resultado = db.query(func.max(cast(Vehiculo_Origen.numero_ingreso, Integer))).scalar()
    
    # Regla de Negocio: Si la tabla está vacía (Día 1 de operaciones)
    if resultado is None:
        siguiente_numero = 1
    else:
        # Sumamos 1 al número más alto encontrado
        siguiente_numero = resultado + 1
        
    return {"siguiente_ingreso": str(siguiente_numero)}

@router.get("/siguiente-para-forzar", status_code=200)
def obtener_siguiente_para_forzar(db: Session = Depends(get_db), usuario_logeado: models.Usuario = Depends(get_current_user)):
    """
    Busca el vehículo más antiguo (numero_ingreso) donde NINGUNO de sus activos inventariados
    haya sido paletizado (ubicacion_pasillo no es nulo y es distinto de 'S/P').
    """
    estado_desarme = db.query(models.Estado_Activo).filter(models.Estado_Activo.nombre_estado == "Desarme").first()
    id_desarme = estado_desarme.id_estado if estado_desarme else 5

    vehiculo = db.query(models.Vehiculo_Origen).filter(
        models.Vehiculo_Origen.numero_ingreso.isnot(None),
        db.query(models.Activo_Inventariado).filter(
            models.Activo_Inventariado.id_vehiculo == models.Vehiculo_Origen.id_vehiculo
        ).exists(),
        ~db.query(models.Activo_Inventariado).filter(
            models.Activo_Inventariado.id_vehiculo == models.Vehiculo_Origen.id_vehiculo,
            models.Activo_Inventariado.id_estado != id_desarme
        ).exists()
    ).order_by(cast(models.Vehiculo_Origen.numero_ingreso, Integer).asc()).first()

    if not vehiculo:
        raise HTTPException(
            status_code=404,
            detail="No hay vehículos vírgenes disponibles para forzar (todos tienen al menos un activo que no está en estado Desarme)."
        )

    # Fetch motor and caja details
    activo_motor = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 1 # Motor
    ).first()
    
    activo_caja = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 2 # Caja
    ).first()

    detalle_motor = db.query(models.Detalle_Motor).filter(models.Detalle_Motor.id_activo == activo_motor.id_activo).first() if activo_motor else None
    detalle_caja = db.query(models.Detalle_Caja_Cambio).filter(models.Detalle_Caja_Cambio.id_activo == activo_caja.id_activo).first() if activo_caja else None

    return {
        "id_vehiculo": str(vehiculo.id_vehiculo),
        "numero_ingreso": vehiculo.numero_ingreso,
        "marca": vehiculo.marca,
        "modelo": vehiculo.modelo,
        "anio": vehiculo.anio,
        "traccion": vehiculo.traccion,
        "motor": {
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "",
            "combustible": detalle_motor.combustible if detalle_motor else "",
            "transmision_tipo": detalle_motor.transmision_tipo if detalle_motor else ""
        },
        "caja": {
            "transmision_tipo": detalle_caja.transmision_tipo if detalle_caja else ""
        }
    }

@router.put("/forzar/{id_vehiculo}", status_code=200)
def forzar_ingreso_vehiculo(
    id_vehiculo: str,
    payload: schemas.VehiculoForzadoUpdate,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user)
):
    vehiculo = db.query(models.Vehiculo_Origen).filter(models.Vehiculo_Origen.id_vehiculo == id_vehiculo).first()
    if not vehiculo:
        raise HTTPException(status_code=404, detail="Vehículo no encontrado")

    # Update Vehiculo
    vehiculo.marca = payload.marca
    vehiculo.modelo = payload.modelo
    vehiculo.anio = payload.anio
    vehiculo.traccion = payload.traccion

    # Update Motor
    activo_motor = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 1
    ).first()
    if activo_motor:
        detalle_motor = db.query(models.Detalle_Motor).filter(models.Detalle_Motor.id_activo == activo_motor.id_activo).first()
        if detalle_motor:
            detalle_motor.cilindrada = payload.motor.cilindrada
            detalle_motor.combustible = payload.motor.combustible
            detalle_motor.transmision_tipo = payload.motor.transmision_tipo

    # Update Caja
    activo_caja = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 2
    ).first()
    if activo_caja:
        detalle_caja = db.query(models.Detalle_Caja_Cambio).filter(models.Detalle_Caja_Cambio.id_activo == activo_caja.id_activo).first()
        if detalle_caja:
            detalle_caja.transmision_tipo = payload.caja.transmision_tipo

    db.commit()
    return {"status": "success", "mensaje": "Datos forzados correctamente", "numero_ingreso": vehiculo.numero_ingreso}

@router.post("/", response_model=schemas.VehiculoResponse, status_code=201)
async def registrar_ingreso_vehiculo(
    # --- NUEVO: Recibimos los datos y la foto por separado (Multipart) ---
    datos: str = Form(...),
    foto: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user)
):
    """
    Registra un vehículo y sus componentes principales (Motor y Caja) previa validación Poka-Yoke.
    """
    # 1. DESEMPACAR EL JSON QUE VIENE DESDE FLUTTER
    try:
        datos_dict = json.loads(datos)
        vehiculo_in = schemas.VehiculoCreate(**datos_dict) 
    except Exception as e:
        raise HTTPException(status_code=422, detail="Error al leer los datos del vehículo")

    # ==========================================
    # 1.5 NORMALIZACIÓN Y PRE-VALIDACIÓN (HU-2.2 / SPEC-22)
    # ==========================================
    patente_raw = (vehiculo_in.patente or "").strip().upper()
    es_sppu = vehiculo_in.es_sppu or not patente_raw or patente_raw in ["S/PPU", "SPPU", "S/P", "SIN PATENTE", "S/PATENTE"]

    if not es_sppu and patente_raw:
        patente_normalizada = patente_raw
        vehiculo_existente = db.query(models.Vehiculo_Origen).filter(
            models.Vehiculo_Origen.patente == patente_normalizada
        ).first()
        if vehiculo_existente:
            raise HTTPException(
                status_code=400, 
                detail=f"La patente {patente_normalizada} ya se encuentra registrada en el sistema."
            )
    else:
        patente_normalizada = None

    # ==========================================
    # 2. ADUANA POKA-YOKE (GOOGLE CLOUD VISION REAL)
    # ==========================================
    print("\n" + "="*40)
    print("🛂 INICIANDO VALIDACIÓN POKA-YOKE CON INTELIGENCIA ARTIFICIAL")
    print("="*40)
    
    numero_esperado = datos_dict.get("correlativo_ingreso")
    print(f"📸 Foto recibida: {foto.filename}")
    print(f"🔍 Buscando el folio {numero_esperado} en la imagen...")

    # A. Leer los bytes físicos de la imagen que envió Flutter
    contenido_imagen = await foto.read()

    # B. Inicializar el cliente de Google y empaquetar la foto
    cliente_vision = vision.ImageAnnotatorClient()
    imagen_vision = vision.Image(content=contenido_imagen)

    # C. Llamar a la nube de Google para extraer los textos
    respuesta = cliente_vision.text_detection(image=imagen_vision)
    textos_detectados = respuesta.text_annotations

    # D. Validar que Google no haya devuelto un error de servidor
    if respuesta.error.message:
        raise HTTPException(status_code=500, detail=f"Error en Google Vision: {respuesta.error.message}")

    # E. Comprobar si Google encontró letras o números
    if not textos_detectados:
        print("❌ ERROR: La IA no detectó ningún texto en la foto.")
        raise HTTPException(status_code=400, detail="No se detectó texto en la imagen. Escribe más claro.")

    # F. Extraer el texto crudo leído por la IA
    texto_completo = textos_detectados[0].description
    print(f"🧠 Texto crudo detectado por la IA:\n{texto_completo}")

    # G. Validación Industrial: ¿El número del sistema está escrito en la foto?
    if str(numero_esperado) not in texto_completo:
        print(f"❌ ERROR: El folio {numero_esperado} no está escrito en la foto.")
        raise HTTPException(status_code=400, detail="Validación Poka-Yoke fallida: La foto no corresponde al vehículo.")

    print("✅ Poka-Yoke superado. IA confirma que la foto es legítima.")
    print("="*40 + "\n")

    # H. REBOBINAR LA FOTO (Paso crítico)
    # Como leímos la foto para la IA, el cursor de memoria quedó al final.
    # Debemos regresarlo a cero para que el código de base de datos pueda guardarla después.
    await foto.seek(0)

    # ==========================================
    # 3. GUARDAR EN LA BASE DE DATOS
    # ==========================================
    try:
        # 3.1 Calcular el correlativo definitivo y bloquearlo
        max_ingreso = db.query(func.max(cast(models.Vehiculo_Origen.numero_ingreso, Integer))).scalar()
        nuevo_numero_ingreso = str(1000) if max_ingreso is None else str(max_ingreso + 1)
        patente_final = f"SPPU-{nuevo_numero_ingreso}" if not patente_normalizada else patente_normalizada

        fecha_ingreso_dt = datetime.now().date()
        if vehiculo_in.fecha_ingreso and vehiculo_in.fecha_ingreso.strip():
            try:
                fecha_ingreso_dt = datetime.strptime(vehiculo_in.fecha_ingreso.strip(), "%Y-%m-%d").date()
            except ValueError:
                pass

        # 3.2 Crear la "Cabecera" (El Vehículo con las 13 columnas completas)
        nuevo_vehiculo = models.Vehiculo_Origen(
            numero_ingreso=nuevo_numero_ingreso,
            patente=patente_final,
            factura=vehiculo_in.factura.strip() if vehiculo_in.factura else None,
            fecha_ingreso=fecha_ingreso_dt,
            origen=vehiculo_in.origen.strip().upper() if vehiculo_in.origen else None,
            marca=vehiculo_in.marca.strip() if vehiculo_in.marca else "",
            modelo=vehiculo_in.modelo.strip() if vehiculo_in.modelo else "",
            anio=vehiculo_in.anio,
            color=vehiculo_in.color.strip().upper() if vehiculo_in.color else None,
            numero_motor=vehiculo_in.numero_motor.strip().upper() if vehiculo_in.numero_motor else None,
            destino=vehiculo_in.destino.strip().upper() if vehiculo_in.destino else "DESARME",
            grua=vehiculo_in.grua.strip().upper() if vehiculo_in.grua else None,
            observaciones=vehiculo_in.observaciones.strip() if vehiculo_in.observaciones else None,
            traccion=vehiculo_in.traccion,
            estado="Activo",
            fecha_creacion=datetime.now()
        )
        db.add(nuevo_vehiculo)
        db.flush()  

        # --- A. MOTOR ---
        activo_motor = models.Activo_Inventariado(
            sku_qr_fisico=f"MOT-{nuevo_numero_ingreso}", 
            id_categoria=1, 
            id_estado=5,    
            id_sucursal_actual=1, 
            id_vehiculo=nuevo_vehiculo.id_vehiculo 
        )
        db.add(activo_motor)
        db.flush() 

        detalle_motor = models.Detalle_Motor(
            id_activo=activo_motor.id_activo, 
            numero_motor=vehiculo_in.numero_motor,
            cilindrada=vehiculo_in.cilindrada,
            combustible=vehiculo_in.combustible,
            transmision_tipo=vehiculo_in.transmision
        )
        db.add(detalle_motor)

        # --- B. CAJA DE CAMBIOS ---
        activo_caja = models.Activo_Inventariado(
            sku_qr_fisico=f"CAJ-{nuevo_numero_ingreso}",
            id_categoria=2, 
            id_estado=5,
            id_sucursal_actual=1,
            id_vehiculo=nuevo_vehiculo.id_vehiculo
        )
        db.add(activo_caja)
        db.flush()

        detalle_caja = models.Detalle_Caja_Cambio(
            id_activo=activo_caja.id_activo,
            transmision_tipo=vehiculo_in.transmision
        )
        db.add(detalle_caja)

        # 3.3 Confirmar la Transacción Completa (ACID)
        db.commit()
        db.refresh(nuevo_vehiculo) 

        # Devolvemos el auto al frontend
        return nuevo_vehiculo

    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error crítico en la transacción: {str(e)}")


@router.post("/registro-manual", response_model=schemas.VehiculoResponse, status_code=201)
def registrar_ingreso_vehiculo_manual(
    vehiculo_in: schemas.VehiculoCreate,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user),
):
    """
    [Fallback Contingencia] Permite el registro manual de un vehículo
    tras confirmación explícita del operario ante fallas de Google Vision u OCR.
    """
    patente_raw = (vehiculo_in.patente or "").strip().upper()
    es_sppu = vehiculo_in.es_sppu or not patente_raw or patente_raw in ["S/PPU", "SPPU", "S/P", "SIN PATENTE", "S/PATENTE"]

    if not es_sppu and patente_raw:
        patente_normalizada = patente_raw
        vehiculo_existente = db.query(models.Vehiculo_Origen).filter(
            models.Vehiculo_Origen.patente == patente_normalizada
        ).first()
        if vehiculo_existente:
            raise HTTPException(
                status_code=400,
                detail=f"La patente {patente_normalizada} ya se encuentra registrada en el sistema.",
            )
    else:
        patente_normalizada = None

    try:
        max_ingreso = db.query(func.max(cast(models.Vehiculo_Origen.numero_ingreso, Integer))).scalar()
        nuevo_numero_ingreso = str(1000) if max_ingreso is None else str(max_ingreso + 1)
        if vehiculo_in.correlativo_ingreso and vehiculo_in.correlativo_ingreso != "Cargando...":
            nuevo_numero_ingreso = vehiculo_in.correlativo_ingreso.strip()

        patente_final = f"SPPU-{nuevo_numero_ingreso}" if not patente_normalizada else patente_normalizada

        fecha_ingreso_dt = datetime.now().date()
        if vehiculo_in.fecha_ingreso and vehiculo_in.fecha_ingreso.strip():
            try:
                fecha_ingreso_dt = datetime.strptime(vehiculo_in.fecha_ingreso.strip(), "%Y-%m-%d").date()
            except ValueError:
                pass

        nuevo_vehiculo_id = uuid.uuid4()
        nuevo_vehiculo = models.Vehiculo_Origen(
            id_vehiculo=nuevo_vehiculo_id,
            numero_ingreso=nuevo_numero_ingreso,
            patente=patente_final,
            factura=vehiculo_in.factura.strip() if vehiculo_in.factura else None,
            fecha_ingreso=fecha_ingreso_dt,
            origen=vehiculo_in.origen.strip().upper() if vehiculo_in.origen else None,
            marca=vehiculo_in.marca.strip() if vehiculo_in.marca else "",
            modelo=vehiculo_in.modelo.strip() if vehiculo_in.modelo else "",
            anio=vehiculo_in.anio,
            color=vehiculo_in.color.strip().upper() if vehiculo_in.color else None,
            numero_motor=vehiculo_in.numero_motor.strip().upper() if vehiculo_in.numero_motor else None,
            destino=vehiculo_in.destino.strip().upper() if vehiculo_in.destino else "DESARME",
            grua=vehiculo_in.grua.strip().upper() if vehiculo_in.grua else None,
            observaciones=vehiculo_in.observaciones.strip() if vehiculo_in.observaciones else None,
            traccion=vehiculo_in.traccion,
            estado="Activo",
            fecha_creacion=datetime.now(),
        )
        db.add(nuevo_vehiculo)
        db.flush()

        id_motor = uuid.uuid4()
        activo_motor = models.Activo_Inventariado(
            id_activo=id_motor,
            sku_qr_fisico=f"MOT-{nuevo_numero_ingreso}",
            id_categoria=1,
            id_estado=5,
            id_sucursal_actual=getattr(usuario_logeado, "id_sucursal", 1) or 1,
            id_vehiculo=nuevo_vehiculo_id,
            estado="Activo",
            fecha_creacion=datetime.now(),
            qr_impreso=False,
        )
        db.add(activo_motor)
        db.flush()

        detalle_motor = models.Detalle_Motor(
            id_activo=id_motor,
            numero_motor=vehiculo_in.numero_motor,
            cilindrada=vehiculo_in.cilindrada,
            combustible=vehiculo_in.combustible,
            transmision_tipo=vehiculo_in.transmision,
        )
        db.add(detalle_motor)

        id_caja = uuid.uuid4()
        activo_caja = models.Activo_Inventariado(
            id_activo=id_caja,
            sku_qr_fisico=f"CAJ-{nuevo_numero_ingreso}",
            id_categoria=2,
            id_estado=5,
            id_sucursal_actual=getattr(usuario_logeado, "id_sucursal", 1) or 1,
            id_vehiculo=nuevo_vehiculo_id,
            estado="Activo",
            fecha_creacion=datetime.now(),
            qr_impreso=False,
        )
        db.add(activo_caja)
        db.flush()

        detalle_caja = models.Detalle_Caja_Cambio(
            id_activo=id_caja,
            transmision_tipo=vehiculo_in.transmision,
        )
        db.add(detalle_caja)

        db.commit()
        db.refresh(nuevo_vehiculo)
        return nuevo_vehiculo
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error crítico en la transacción: {str(e)}")


# ==========================================
# 2. RUTAS DE INVENTARIO Y PALETIZADO
# ==========================================

@router.get("/pendientes-paletizado", status_code=200)
def obtener_pendientes_paletizado(
    sucursal_id: Optional[int] = None,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user),
):
    """
    Lista todos los activos de inventario pendientes de paletizado de la sucursal activa
    (ubicacion_pasillo IS NULL, ubicacion_pasillo == 'S/P', o id_estado == 5).
    """
    from sqlalchemy import or_

    suc_target = sucursal_id or getattr(usuario_logeado, "id_sucursal", 1) or 1

    query = (
        db.query(
            models.Activo_Inventariado,
            models.Vehiculo_Origen,
            models.Categoria_Activo,
            models.Estado_Activo,
        )
        .outerjoin(models.Vehiculo_Origen, models.Activo_Inventariado.id_vehiculo == models.Vehiculo_Origen.id_vehiculo)
        .join(models.Categoria_Activo, models.Activo_Inventariado.id_categoria == models.Categoria_Activo.id_categoria)
        .join(models.Estado_Activo, models.Activo_Inventariado.id_estado == models.Estado_Activo.id_estado)
        .filter(
            models.Activo_Inventariado.estado == "Activo",
            models.Activo_Inventariado.id_sucursal_actual == suc_target,
            models.Activo_Inventariado.id_estado == 5,
            or_(
                models.Activo_Inventariado.ubicacion_pasillo == None,
                models.Activo_Inventariado.ubicacion_pasillo == "",
                models.Activo_Inventariado.ubicacion_pasillo == "S/P",
                models.Activo_Inventariado.ubicacion_pallet == None,
                models.Activo_Inventariado.ubicacion_pallet == "",
                models.Activo_Inventariado.ubicacion_pallet == "S/P",
            ),
        )
        .order_by(models.Activo_Inventariado.fecha_creacion.desc())
    )

    resultados = query.all()

    respuesta = []
    for activo, vehiculo, cat, est in resultados:
        respuesta.append({
            "id_activo": str(activo.id_activo),
            "sku_qr_fisico": activo.sku_qr_fisico,
            "id_categoria": cat.id_categoria,
            "tipo_repuesto": cat.nombre_categoria,
            "numero_ingreso": vehiculo.numero_ingreso if vehiculo else "N/A",
            "marca": vehiculo.marca if vehiculo else "Desconocida",
            "modelo": vehiculo.modelo if vehiculo else "Desconocido",
            "anio": vehiculo.anio if vehiculo else 0,
            "patente": vehiculo.patente if vehiculo else None,
            "estado": est.nombre_estado,
            "fecha_creacion": activo.fecha_creacion.isoformat() if activo.fecha_creacion else None,
        })

    return respuesta

@router.get("/buscar/{numero_ingreso}")
def buscar_vehiculo_por_ingreso(numero_ingreso: str, db: Session = Depends(get_db), usuario_logeado: models.Usuario = Depends(get_current_user)):
    """
    Busca los datos de un vehículo por su número de ingreso (Folio).
    Retorna los datos del vehículo y los detalles técnicos de sus repuestos (Motor y Caja).
    """
    print(f"\n🔍 Buscando inventario para el folio: {numero_ingreso}")
    
    # 1. Buscar el vehículo base
    vehiculo = db.query(models.Vehiculo_Origen).filter(models.Vehiculo_Origen.numero_ingreso == numero_ingreso).first()
    
    if not vehiculo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró un vehículo registrado con el folio '{numero_ingreso}'"
        )

    # 2. Buscar el activo MOTOR (Categoría 1) y sus detalles
    activo_motor = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 1 # Asumiendo que 1 es Motor
    ).first()

    detalle_motor = None
    if activo_motor:
        detalle_motor = db.query(models.Detalle_Motor).filter(
            models.Detalle_Motor.id_activo == activo_motor.id_activo
        ).first()

    # 3. Buscar el activo CAJA DE CAMBIOS (Categoría 2) y sus detalles
    activo_caja = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 2 # Asumiendo que 2 es Caja
    ).first()

    detalle_caja = None
    if activo_caja:
        detalle_caja = db.query(models.Detalle_Caja_Cambio).filter(
            models.Detalle_Caja_Cambio.id_activo == activo_caja.id_activo
        ).first()

    # 4. Empaquetar todo en un JSON amigable para Flutter
    return {
        "vehiculo": {
            "marca": vehiculo.marca,
            "modelo": vehiculo.modelo,
            "anio": vehiculo.anio,
            "traccion": vehiculo.traccion,
        },
        "motor": {
            "id_activo": str(activo_motor.id_activo) if activo_motor else None,
            "id_estado": activo_motor.id_estado if activo_motor else None, # ⚠️ NUEVO
            "numero_motor": detalle_motor.numero_motor if detalle_motor else "S/A",
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "S/A",
            "combustible": detalle_motor.combustible if detalle_motor else "S/A",
            "transmision_tipo": detalle_motor.transmision_tipo if detalle_motor else "S/A",
            "traccion": vehiculo.traccion if vehiculo else "S/A",
        },
        "caja_cambios": {
            "id_activo": str(activo_caja.id_activo) if activo_caja else None,
            "id_estado": activo_caja.id_estado if activo_caja else None, # ⚠️ NUEVO
            "transmision_tipo": detalle_caja.transmision_tipo if detalle_caja else "S/A",
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "S/A",
            "combustible": detalle_motor.combustible if detalle_motor else "S/A",
            "traccion": vehiculo.traccion if vehiculo else "S/A",
        }
    }

@router.get("/buscar-motor/{numero_motor}")
def buscar_vehiculo_por_numero_motor(
    numero_motor: str,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user)
):
    """
    Busca los datos de un vehículo y su número de ingreso a partir del número de motor (Detalle_Motor).
    Permite iniciar el flujo de paletizado cuando el motor físico no tiene rotulado el folio de ingreso.
    """
    termino = numero_motor.strip()
    if not termino:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El número de motor no puede estar vacío."
        )

    # 1. Búsqueda exacta (case-insensitive)
    detalle_motor = db.query(models.Detalle_Motor).join(
        models.Activo_Inventariado,
        models.Detalle_Motor.id_activo == models.Activo_Inventariado.id_activo
    ).join(
        models.Vehiculo_Origen,
        models.Activo_Inventariado.id_vehiculo == models.Vehiculo_Origen.id_vehiculo
    ).filter(
        func.lower(func.trim(models.Detalle_Motor.numero_motor)) == func.lower(termino)
    ).first()

    # 2. Si no hay coincidencia exacta y el término tiene al menos 4 caracteres, intentar coincidencia parcial
    if not detalle_motor and len(termino) >= 4:
        detalle_motor = db.query(models.Detalle_Motor).join(
            models.Activo_Inventariado,
            models.Detalle_Motor.id_activo == models.Activo_Inventariado.id_activo
        ).join(
            models.Vehiculo_Origen,
            models.Activo_Inventariado.id_vehiculo == models.Vehiculo_Origen.id_vehiculo
        ).filter(
            models.Detalle_Motor.numero_motor.ilike(f"%{termino}%"),
            ~models.Detalle_Motor.numero_motor.in_(["S/A", "SN", "S/N", "NONE", "NAN", "0"])
        ).first()

    if not detalle_motor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún motor registrado con el número '{numero_motor}'"
        )

    activo_motor = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_activo == detalle_motor.id_activo
    ).first()

    vehiculo = db.query(models.Vehiculo_Origen).filter(
        models.Vehiculo_Origen.id_vehiculo == activo_motor.id_vehiculo
    ).first() if activo_motor else None

    if not vehiculo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="El motor encontrado no tiene un vehículo de origen asociado."
        )

    # Buscar activo Caja de Cambios (Categoría 2) para el mismo vehículo
    activo_caja = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        models.Activo_Inventariado.id_categoria == 2
    ).first()

    detalle_caja = None
    if activo_caja:
        detalle_caja = db.query(models.Detalle_Caja_Cambio).filter(
            models.Detalle_Caja_Cambio.id_activo == activo_caja.id_activo
        ).first()

    return {
        "numero_ingreso": vehiculo.numero_ingreso,
        "id_vehiculo": str(vehiculo.id_vehiculo),
        "vehiculo": {
            "marca": vehiculo.marca,
            "modelo": vehiculo.modelo,
            "anio": vehiculo.anio,
            "traccion": vehiculo.traccion,
            "numero_ingreso": vehiculo.numero_ingreso,
            "patente": vehiculo.patente,
        },
        "motor": {
            "id_activo": str(activo_motor.id_activo) if activo_motor else None,
            "id_estado": activo_motor.id_estado if activo_motor else None,
            "numero_motor": detalle_motor.numero_motor if detalle_motor else "S/A",
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "S/A",
            "combustible": detalle_motor.combustible if detalle_motor else "S/A",
            "transmision_tipo": detalle_motor.transmision_tipo if detalle_motor else "S/A",
            "traccion": vehiculo.traccion if vehiculo else "S/A",
        },
        "caja_cambios": {
            "id_activo": str(activo_caja.id_activo) if activo_caja else None,
            "id_estado": activo_caja.id_estado if activo_caja else None,
            "transmision_tipo": detalle_caja.transmision_tipo if detalle_caja else "S/A",
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "S/A",
            "combustible": detalle_motor.combustible if detalle_motor else "S/A",
            "traccion": vehiculo.traccion if vehiculo else "S/A",
        }
    }

@router.post("/validar-ocr-pieza")
async def validar_ocr_pieza(
    numero_ingreso: str = Form(...),
    imagen_posca: UploadFile = File(...),
    usuario_logeado: models.Usuario = Depends(get_current_user)
):
    """
    [Poka-Yoke Digital] - HU-2.3
    Recibe la fotografía de la pieza con el número escrito en Posca.
    Utiliza Google Cloud Vision OCR para verificar que el número físico 
    coincida con el folio en el sistema.
    """
    print("\n" + "="*40)
    print("🛂 INICIANDO VALIDACIÓN POKA-YOKE DE PIEZA (OCR)")
    print("="*40)
    
    print(f"📸 Foto recibida: {imagen_posca.filename}")
    print(f"🔍 Buscando el folio '{numero_ingreso}' en la pieza...")

    try:
        # 1. Leemos los bytes de la imagen enviada desde Flutter
        contenido_imagen = await imagen_posca.read()
        
        # 2. Preparamos el cliente de Google Vision
        client = vision.ImageAnnotatorClient()
        image = vision.Image(content=contenido_imagen)
        
        # 3. Solicitamos la detección de texto (OCR)
        response = client.text_detection(image=image)
        texts = response.text_annotations
        
        # Si Google no detecta ningún texto en la foto, rechazamos de inmediato
        if not texts:
            print("❌ ERROR: La IA no detectó ningún texto en la fotografía.")
            print("="*40 + "\n")
            return {
                "match": False,
                "mensaje": "No se detectó ningún texto en la fotografía.",
                "texto_detectado": ""
            }
            
        # 4. Extraemos el texto completo detectado y lo limpiamos
        texto_completo = texts[0].description
        print(f"🧠 Texto crudo detectado por la IA:\n{texto_completo}")
        
        # Limpiamos saltos de línea y espacios extras para una búsqueda exacta
        texto_limpio = texto_completo.replace('\n', '').replace(' ', '').strip()
        print(f"🧹 Texto procesado (sin espacios/saltos): '{texto_limpio}'")
        
        # 5. La magia del Poka-Yoke: ¿El folio está escrito en el metal?
        match_exitoso = numero_ingreso in texto_limpio
        
        if match_exitoso:
            print(f"✅ Poka-Yoke superado. Se encontró el folio '{numero_ingreso}' en la pieza.")
        else:
            print(f"❌ ERROR: El folio '{numero_ingreso}' no coincide con lo escrito en la pieza.")
            
        print("="*40 + "\n")
        
        return {
            "match": match_exitoso,
            "mensaje": "Match exitoso" if match_exitoso else f"El número {numero_ingreso} no coincide con lo escrito en la pieza.",
            "texto_detectado": texto_limpio # Útil para depurar en el frontend
        }
        
    except Exception as e:
        print(f"⚠️ ERROR CRÍTICO EN OCR: {str(e)}")
        print("="*40 + "\n")
        # Si Google Cloud falla (ej. sin internet), manejamos el error elegantemente
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error al procesar el OCR con Google Vision: {str(e)}"
        )

@router.post("/guardar-paletizado", status_code=201)
async def guardar_paletizado(
    # --- Datos de Texto ---
    numero_ingreso: str = Form(...),
    tipo_repuesto: str = Form(...), # 'Motor' o 'Caja de Cambios'
    galpon: str = Form(...),
    pasillo: str = Form(...),
    pallet: str = Form(...),
    observaciones: str = Form(None), # Opcional

    # --- Especificaciones Técnicas Editables ---
    cilindrada: Optional[str] = Form(None),
    combustible: Optional[str] = Form(None),
    transmision_tipo: Optional[str] = Form(None),
    numero_motor: Optional[str] = Form(None),
    traccion: Optional[str] = Form(None),
    
    # --- Lista de hasta 10 fotos comerciales ---
    fotos_comerciales: List[UploadFile] = File(...),
    
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user)
):
    """
    [Jefe Final] - HU-2.3 & HU-2.4
    1. Sube las fotos comerciales a Supabase Storage.
    2. Actualiza la ubicación física en PostgreSQL (Activo_Inventariado).
    3. Registra las URLs de las fotos en PostgreSQL (Multimedia_Activo).
    4. Retorna payload enriquecido para generar la etiqueta térmica (HU-2.4).
    """
    
    print("\n" + "="*40)
    print(f"💾 INICIANDO GUARDADO LOGÍSTICO PARA FOLIO {numero_ingreso}")
    print("="*40)

    # 1. Validación de seguridad: ¿Está configurado Supabase?
    if not supabase:
        raise HTTPException(
            status_code=500,
            detail="El servicio de almacenamiento de Supabase no está configurado en el servidor."
        )

    if len(fotos_comerciales) > 10:
        raise HTTPException(status_code=400, detail="Máximo 10 fotografías comerciales permitidas.")

    # ========================================================
    # PASO 1. VALIDACIÓN PREVIA EN BASE DE DATOS
    # ========================================================
    # 1. Buscar el activo específico (Motor o Caja) usando el Folio
    query_activo = db.query(models.Activo_Inventariado).join(models.Vehiculo_Origen).filter(
        models.Vehiculo_Origen.numero_ingreso == numero_ingreso
    )
    
    id_categoria = 1 if tipo_repuesto == "Motor" else 2
    query_activo = query_activo.filter(models.Activo_Inventariado.id_categoria == id_categoria)
    
    activo = query_activo.first()
    
    if not activo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró el activo '{tipo_repuesto}' asociado al folio {numero_ingreso}."
        )

    # 2. Validar que el activo se encuentre en estado 'Desarme' (ID 5)
    if activo.id_estado != 5:
        estado_actual = db.query(models.Estado_Activo).filter(models.Estado_Activo.id_estado == activo.id_estado).first()
        nombre_estado_actual = estado_actual.nombre_estado if estado_actual else f"Estado {activo.id_estado}"
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El repuesto '{tipo_repuesto}' del folio {numero_ingreso} no puede ser paletizado porque se encuentra en estado '{nombre_estado_actual}'. Solo se pueden paletizar repuestos en estado 'Desarme'."
        )

    # ========================================================
    # PASO 2. SUBIR IMÁGENES A SUPABASE STORAGE
    # ========================================================
    urls_fotos_publicas = []
    
    BUCKET_NAME = "multimedia-activos"
    
    try:
        supabase.storage.create_bucket(BUCKET_NAME, options={"public": True})
        print(f"✅ Bucket '{BUCKET_NAME}' creado (o ya existía).")
    except Exception as e:
        print(f"ℹ️ Info sobre Bucket: {str(e)}")
        pass

    prefijo = "moto" if tipo_repuesto == "Motor" else "caja"

    # 1. Leemos los buffers binarios de las fotos asíncronamente
    fotos_data = []
    for i, foto in enumerate(fotos_comerciales):
        contenido = await foto.read()
        nombre_archivo = f"{numero_ingreso}/{prefijo}_{numero_ingreso}_comercial_{i+1}.jpg"
        fotos_data.append((i + 1, nombre_archivo, contenido))

    def _subir_foto_sync(idx: int, path_nube: str, contenido: bytes) -> str:
        supabase.storage.from_(BUCKET_NAME).upload(
            path=path_nube,
            file=contenido,
            file_options={"cache-control": "3600", "content-type": "image/jpeg", "upsert": "true"}
        )
        url = supabase.storage.from_(BUCKET_NAME).get_public_url(path_nube)
        print(f"📸 Foto {idx} subida exitosamente: {path_nube}")
        return url

    # 2. Subida concurrente en hilos paralelos para máxima velocidad
    try:
        urls_fotos_publicas = await asyncio.gather(*[
            asyncio.to_thread(_subir_foto_sync, idx, path_nube, contenido)
            for idx, path_nube, contenido in fotos_data
        ])
    except Exception as e:
        print(f"❌ ERROR al subir fotos a Supabase: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Fallo al subir las fotografías comerciales a la nube ({str(e)}). El guardado ha sido abortado."
        )

    # ========================================================
    # PASO 3. GUARDAR EN POSTGRESQL CON TRANSACCIÓN (SQLAlchemy)
    # ========================================================
    try:
        # Actualizar la Ubicación Física y Observaciones (PERSISTENCIA LOGÍSTICA)
        activo.ubicacion_galpon = galpon
        activo.ubicacion_pasillo = pasillo
        activo.ubicacion_pallet = pallet
        
        if hasattr(activo, 'observacion_estado') and observaciones:
            activo.observacion_estado = observaciones
            
        estado_paletizado = db.query(models.Estado_Activo).filter(models.Estado_Activo.nombre_estado == "Paletizado").first()
        if not estado_paletizado:
            estado_paletizado = models.Estado_Activo(nombre_estado="Paletizado")
            db.add(estado_paletizado)
            db.flush()
            
        activo.id_estado = estado_paletizado.id_estado
        
        db.flush()
        
        # Guardar las URLs de las fotos en Multimedia_Activo (PERSISTENCIA COMERCIAL)
        for url in urls_fotos_publicas:
            nueva_multimedia = models.Multimedia_Activo(
                id_activo=activo.id_activo,
                url_storage=url,
                tipo_archivo="imagen"
            )
            db.add(nueva_multimedia)

        # Actualizar especificaciones técnicas editadas por el usuario
        if tipo_repuesto == "Motor":
            dm = db.query(models.Detalle_Motor).filter(models.Detalle_Motor.id_activo == activo.id_activo).first()
            if not dm:
                dm = models.Detalle_Motor(id_activo=activo.id_activo)
                db.add(dm)
            if cilindrada is not None and cilindrada.strip():
                dm.cilindrada = cilindrada.strip()
            if combustible is not None and combustible.strip():
                dm.combustible = combustible.strip()
            if transmision_tipo is not None and transmision_tipo.strip():
                dm.transmision_tipo = transmision_tipo.strip()
            if numero_motor is not None and numero_motor.strip():
                dm.numero_motor = numero_motor.strip()
        elif tipo_repuesto == "Caja de Cambios":
            dc = db.query(models.Detalle_Caja_Cambio).filter(models.Detalle_Caja_Cambio.id_activo == activo.id_activo).first()
            if not dc:
                dc = models.Detalle_Caja_Cambio(id_activo=activo.id_activo)
                db.add(dc)
            if transmision_tipo is not None and transmision_tipo.strip():
                dc.transmision_tipo = transmision_tipo.strip()

        # Actualizar tracción en Vehiculo_Origen si se especificó
        if traccion is not None and traccion.strip() and activo.id_vehiculo:
            veh_origen = db.query(models.Vehiculo_Origen).filter(models.Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first()
            if veh_origen:
                veh_origen.traccion = traccion.strip()
            
        # Confirmar la transacción completa (ACID)
        db.commit()
        db.refresh(activo)
        
        print(f"✅ Paletizado guardado exitosamente en base de datos para Folio {numero_ingreso}.")
        
        # ========================================================
        # PASO C. EXTRACCIÓN DE DATOS PARA LA ETIQUETA TÉRMICA (HU-2.4)
        # ========================================================
        print("🔍 Extrayendo datos enriquecidos para la previsualización de la etiqueta...")
        
        vehiculo = db.query(models.Vehiculo_Origen).filter(
            models.Vehiculo_Origen.numero_ingreso == numero_ingreso
        ).first()
        
        cilindrada = None
        combustible = None
        transmision = None
        numero_motor = None
        
        if tipo_repuesto == "Motor":
            detalle_motor = db.query(models.Detalle_Motor).filter(
                models.Detalle_Motor.id_activo == activo.id_activo
            ).first()
            if detalle_motor:
                cilindrada = detalle_motor.cilindrada
                combustible = detalle_motor.combustible
                numero_motor = detalle_motor.numero_motor
                transmision = detalle_motor.transmision_tipo
        else:
            detalle_caja = db.query(models.Detalle_Caja_Cambio).filter(
                models.Detalle_Caja_Cambio.id_activo == activo.id_activo
            ).first()
            if detalle_caja:
                transmision = detalle_caja.transmision_tipo
            
            # Herencia de especificaciones del activo hermano Motor (SPEC-HU-TAREA-17)
            if activo.id_vehiculo:
                motor_hermano = (
                    db.query(models.Detalle_Motor)
                    .join(models.Activo_Inventariado, models.Activo_Inventariado.id_activo == models.Detalle_Motor.id_activo)
                    .filter(
                        models.Activo_Inventariado.id_vehiculo == activo.id_vehiculo,
                        models.Activo_Inventariado.id_categoria == 1,
                    )
                    .first()
                )
                if motor_hermano:
                    cilindrada = motor_hermano.cilindrada
                    combustible = motor_hermano.combustible
                
        print(f"🏷️ SKU Generado y enviado a la UI: {activo.sku_qr_fisico}")
        print("="*40 + "\n")
        
        return {
            "status": "success",
            "mensaje": f"Se ha guardado exitosamente el paletizado del '{tipo_repuesto}' (Folio {numero_ingreso}).",
            "urls_fotos": urls_fotos_publicas,
            "id_activo": str(activo.id_activo),
            "sku_qr_fisico": activo.sku_qr_fisico,
            "qr_impreso": activo.qr_impreso if activo.qr_impreso is not None else False,
            "numero_ingreso": numero_ingreso,
            "marca": vehiculo.marca if vehiculo else "S/A",
            "modelo": vehiculo.modelo if vehiculo else "S/A",
            "anio": vehiculo.anio if vehiculo else 0,
            "traccion": vehiculo.traccion if vehiculo else None,
            "galpon": galpon,
            "pasillo": pasillo,
            "pallet": pallet,
            "cilindrada": cilindrada,
            "combustible": combustible,
            "transmision": transmision,
            "numero_motor": numero_motor
        }

    except Exception as e:
        print(f"⚠️ ERROR CRÍTICO EN BASE DE DATOS: {str(e)}. Iniciando Rollback de Storage.")
        db.rollback()

        for url in urls_fotos_publicas:
            try:
                parts = url.split(f"{BUCKET_NAME}/")
                if len(parts) == 2:
                    nombre_archivo = parts[1]
                    supabase.storage.from_(BUCKET_NAME).remove([nombre_archivo])
                    print(f"🧹 Archivo revertido de la nube: {nombre_archivo}")
            except Exception as se:
                print(f"⚠️ No se pudo revertir el archivo de la nube: {str(se)}")
                
        raise HTTPException(
            status_code=500,
            detail=f"Error crítico al guardar en PostgreSQL: {str(e)}. Los datos y archivos se han revertido para mantener la integridad."
        )

# ==========================================
# PATCH: Confirmar Impresión de Etiqueta QR (HU-2.4 Fase 4)
# ==========================================

@router.patch("/inventario/{id_activo}/impreso", status_code=200)
def marcar_qr_impreso(
    id_activo: str,
    payload: schemas.ActualizarQrImpresoRequest,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user)
):
    """
    Marca el campo qr_impreso de un Activo_Inventariado como True (o False).
    Llamado automáticamente desde la PDA Sunmi L3 tras una impresión física exitosa.
    """
    print(f"📌 [INVENTARIO] 🖨️ PATCH qr_impreso={payload.qr_impreso} para id_activo: {id_activo}")

    activo = db.query(models.Activo_Inventariado).filter(
        models.Activo_Inventariado.id_activo == id_activo
    ).first()

    if not activo:
        raise HTTPException(
            status_code=404,
            detail=f"Activo inventariado con ID '{id_activo}' no encontrado."
        )

    activo.qr_impreso = payload.qr_impreso
    db.commit()
    db.refresh(activo)

    print(f"📌 [INVENTARIO] ✅ qr_impreso={activo.qr_impreso} guardado exitosamente en BD.")

    return {
        "status": "success",
        "mensaje": "Estado de etiqueta QR actualizado exitosamente.",
        "id_activo": str(activo.id_activo),
        "qr_impreso": activo.qr_impreso
    }


# ==========================================
# 3. RUTAS DINÁMICAS (Al final del archivo)
# ==========================================

@router.get("/{patente}", response_model=schemas.VehiculoResponse, status_code=200)
def obtener_vehiculo(
    patente: str,
    db: Session = Depends(get_db),
    usuario_logeado: models.Usuario = Depends(get_current_user),
):
    """
    Busca un vehículo por su patente en PostgreSQL. Si no existe, acciona el motor de Scraping 
    para registrarlo automáticamente.
    """
    try:
        patente_validada = schemas.PatenteInput(patente=patente).patente
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    vehiculo = procesar_patente_y_guardar(db=db, patente_limpia=patente_validada)
    return vehiculo