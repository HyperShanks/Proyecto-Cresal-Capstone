from sqlalchemy.orm import Session
from fastapi import HTTPException
import models
# ⚠️ Se eliminó la importación de scraping que causaba el error 500 en Render
# y también eliminamos 'uuid' porque ya no creamos registros de contingencia aquí.

def procesar_patente_y_guardar(db: Session, patente_limpia: str):
    """
    Verifica si un vehículo ya existe en la base de datos local.
    (El web scraping y la creación del registro ahora los maneja la PDA vía Flutter).
    """
    # 1. Consulta a PostgreSQL
    vehiculo_db = db.query(models.Vehiculo_Origen).filter(models.Vehiculo_Origen.patente == patente_limpia).first()
    
    if vehiculo_db:
        return vehiculo_db 
        
    # 2. Si no existe, simplemente lanzamos un 404. 
    # El Frontend en Flutter atrapará esto, hará el scraping nativo con la PDA 
    # y luego enviará los datos correctos por el endpoint POST para guardarlo.
    raise HTTPException(
        status_code=404, 
        detail=f"El vehículo con patente {patente_limpia} no está registrado en el sistema."
    )