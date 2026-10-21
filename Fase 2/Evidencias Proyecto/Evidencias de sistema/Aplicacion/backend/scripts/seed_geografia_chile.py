# backend/scripts/seed_geografia_chile.py
"""
Script idempotente para poblar las 16 regiones oficiales y 346 comunas de Chile
en las tablas 'Region' y 'Comuna' de la base de datos Supabase / PostgreSQL.
Preserva los IDs existentes (ej. Region 1: Valparaíso, Comuna 1: Viña del Mar, Comuna 2: Limache).
"""

import sys
import os

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Asegurar que el backend esté en el path de importación
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import text
from database import SessionLocal, engine
from models import Region, Comuna

REGIONES_CHILE = [
    (1, "Valparaíso"),
    (2, "Arica y Parinacota"),
    (3, "Tarapacá"),
    (4, "Antofagasta"),
    (5, "Atacama"),
    (6, "Coquimbo"),
    (7, "Metropolitana de Santiago"),
    (8, "Libertador General Bernardo O'Higgins"),
    (9, "Maule"),
    (10, "Ñuble"),
    (11, "Biobío"),
    (12, "La Araucanía"),
    (13, "Los Ríos"),
    (14, "Los Lagos"),
    (15, "Aysén del General Carlos Ibáñez del Campo"),
    (16, "Magallanes y de la Antártica Chilena"),
]

COMUNAS_POR_REGION = {
    "Valparaíso": [
        "Viña del Mar", "Limache", "Algarrobo", "Cabildo", "Calle Larga", "Cartagena",
        "Casablanca", "Catemu", "Concón", "El Quisco", "El Tabo", "Hijuelas",
        "Isla de Pascua", "Juan Fernández", "La Calera", "La Cruz", "La Ligua",
        "Llay Llay", "Los Andes", "Nogales", "Olmué", "Panquehue", "Papudo",
        "Petorca", "Puchuncaví", "Putaendo", "Quillota", "Quilpué", "Quintero",
        "Rinconada", "San Antonio", "San Esteban", "San Felipe", "Santa María",
        "Santo Domingo", "Valparaíso", "Villa Alemana", "Zapallar"
    ],
    "Arica y Parinacota": [
        "Arica", "Camarones", "General Lagos", "Putre"
    ],
    "Tarapacá": [
        "Alto Hospicio", "Camiña", "Colchane", "Huara", "Iquique", "Pica", "Pozo Almonte"
    ],
    "Antofagasta": [
        "Antofagasta", "Calama", "María Elena", "Mejillones", "Ollagüe",
        "San Pedro de Atacama", "Sierra Gorda", "Taltal", "Tocopilla"
    ],
    "Atacama": [
        "Alto del Carmen", "Caldera", "Chañaral", "Copiapó", "Diego de Almagro",
        "Freirina", "Huasco", "Tierra Amarilla", "Vallenar"
    ],
    "Coquimbo": [
        "Andacollo", "Canela", "Combarbalá", "Coquimbo", "Illapel", "La Higuera",
        "La Serena", "Los Vilos", "Monte Patria", "Ovalle", "Paihuano", "Punitaqui",
        "Río Hurtado", "Salamanca", "Vicuña"
    ],
    "Metropolitana de Santiago": [
        "Alhué", "Buin", "Calera de Tango", "Cerrillos", "Cerro Navia", "Colina",
        "Conchalí", "Curacaví", "El Bosque", "El Monte", "Estación Central",
        "Huechuraba", "Independencia", "Isla de Maipo", "La Cisterna", "La Florida",
        "La Granja", "La Pintana", "La Reina", "Lampa", "Las Condes", "Lo Barnechea",
        "Lo Espejo", "Lo Prado", "Macul", "Maipú", "María Pinto", "Melipilla",
        "Padre Hurtado", "Paine", "Pedro Aguirre Cerda", "Peñaflor", "Peñalolén",
        "Pirque", "Providencia", "Pudahuel", "Puente Alto", "Quilicura",
        "Quinta Normal", "Recoleta", "Renca", "San Bernardo", "San Joaquín",
        "San José de Maipo", "San Miguel", "San Pedro", "San Ramón", "Santiago",
        "Talagante", "Tiltil", "Vitacura", "Ñuñoa"
    ],
    "Libertador General Bernardo O'Higgins": [
        "Chimbarongo", "Chépica", "Codegua", "Coinco", "Coltauco", "Doñihue",
        "Graneros", "La Estrella", "Las Cabras", "Litueche", "Lolol", "Machalí",
        "Malloa", "Marchihue", "Mostazal", "Nancagua", "Navidad", "Olivar",
        "Palmilla", "Paredones", "Peralillo", "Peumo", "Pichidegua", "Pichilemu",
        "Placilla", "Pumanque", "Quinta de Tilcoco", "Rancagua", "Rengo", "Requínoa",
        "San Fernando", "San Vicente", "Santa Cruz"
    ],
    "Maule": [
        "Cauquenes", "Chanco", "Colbún", "Constitución", "Curepto", "Curicó",
        "Empedrado", "Hualañé", "Licantén", "Linares", "Longaví", "Maule",
        "Molina", "Parral", "Pelarco", "Pelluhue", "Pencahue", "Rauco",
        "Retiro", "Romeral", "Río Claro", "Sagrada Familia", "San Clemente",
        "San Javier", "San Rafael", "Talca", "Teno", "Vichuquén", "Villa Alegre",
        "Yerbas Buenas"
    ],
    "Ñuble": [
        "Bulnes", "Chillán", "Chillán Viejo", "Cobquecura", "Coelemu", "Coihueco",
        "El Carmen", "Ninhue", "Pemuco", "Pinto", "Portezuelo", "Quillón",
        "Quirihue", "Ránquil", "San Carlos", "San Fabián", "San Ignacio",
        "San Nicolás", "Treguaco", "Yungay", "Ñiquén"
    ],
    "Biobío": [
        "Alto Biobío", "Antuco", "Arauco", "Cabrero", "Cañete", "Chiguayante",
        "Concepción", "Contulmo", "Coronel", "Curanilahue", "Florida", "Hualpén",
        "Hualqui", "Laja", "Lebu", "Los Álamos", "Los Ángeles", "Lota",
        "Mulchén", "Nacimiento", "Negrete", "Penco", "Quilaco", "Quilleco",
        "San Pedro de la Paz", "San Rosendo", "Santa Bárbara", "Santa Juana",
        "Talcahuano", "Tirúa", "Tomé", "Tucapel", "Yumbel"
    ],
    "La Araucanía": [
        "Angol", "Carahue", "Cholchol", "Collipulli", "Cunco", "Curacautín",
        "Curarrehue", "Ercilla", "Freire", "Galvarino", "Gorbea", "Lautaro",
        "Loncoche", "Lonquimay", "Los Sauces", "Lumaco", "Melipeuco",
        "Nueva Imperial", "Padre las Casas", "Perquenco", "Pitrufquén", "Pucón",
        "Purén", "Renaico", "Saavedra", "Temuco", "Teodoro Schmidt", "Toltén",
        "Traiguén", "Victoria", "Vilcún", "Villarrica"
    ],
    "Los Ríos": [
        "Corral", "Futrono", "La Unión", "Lago Ranco", "Lanco", "Los Lagos",
        "Mariquina", "Máfil", "Paillaco", "Panguipulli", "Río Bueno", "Valdivia"
    ],
    "Los Lagos": [
        "Ancud", "Calbuco", "Castro", "Chaitén", "Chonchi", "Cochamó",
        "Curaco de Vélez", "Dalcahue", "Fresia", "Frutillar", "Futaleufú",
        "Hualaihué", "Llanquihue", "Los Muermos", "Maullín", "Osorno", "Palena",
        "Puerto Montt", "Puerto Octay", "Puerto Varas", "Puqueldón", "Purranque",
        "Puyehue", "Queilén", "Quellón", "Quemchi", "Quinchao", "Río Negro",
        "San Juan de la Costa", "San Pablo"
    ],
    "Aysén del General Carlos Ibáñez del Campo": [
        "Aysén", "Chile Chico", "Cisnes", "Cochrane", "Coyhaique", "Guaitecas",
        "Lago Verde", "O'Higgins", "Río Ibáñez", "Tortel"
    ],
    "Magallanes y de la Antártica Chilena": [
        "Antártica", "Cabo de Hornos", "Laguna Blanca", "Natales", "Porvenir",
        "Primavera", "Punta Arenas", "Río Verde", "San Gregorio", "Timaukel",
        "Torres del Paine"
    ],
}


def seed_geografia():
    db = SessionLocal()
    try:
        print("🌱 Iniciando sembrado oficial de Geografía de Chile...")

        # 1. Asegurar Regiones
        region_nombre_to_id = {}
        for r_id, r_nom in REGIONES_CHILE:
            reg = db.query(Region).filter(Region.nombre_region == r_nom).first()
            if not reg:
                # Verificar si el ID está libre o usar el asignado
                reg_by_id = db.query(Region).filter(Region.id_region == r_id).first()
                if reg_by_id:
                    reg = Region(nombre_region=r_nom)
                else:
                    reg = Region(id_region=r_id, nombre_region=r_nom)
                db.add(reg)
                db.flush()
                print(f"  + Región creada: [{reg.id_region}] {reg.nombre_region}")
            region_nombre_to_id[r_nom] = reg.id_region

        # 2. Asegurar Comunas
        comunas_creadas = 0
        for r_nom, comunas_lista in COMUNAS_POR_REGION.items():
            id_reg = region_nombre_to_id[r_nom]
            for c_nom in comunas_lista:
                comuna = db.query(Comuna).filter(Comuna.nombre_comuna == c_nom).first()
                if not comuna:
                    comuna = Comuna(nombre_comuna=c_nom, id_region=id_reg)
                    db.add(comuna)
                    comunas_creadas += 1

        db.commit()
        print(f"✅ Se agregaron {comunas_creadas} nuevas comunas.")

        # 3. Sincronizar secuencias de PostgreSQL
        with engine.connect() as conn:
            try:
                conn.execute(text("SELECT setval('\"Region_id_region_seq\"', (SELECT MAX(id_region) FROM \"Region\"));"))
                conn.execute(text("SELECT setval('\"Comuna_id_comuna_seq\"', (SELECT MAX(id_comuna) FROM \"Comuna\"));"))
                conn.commit()
                print("✅ Secuencias de Region y Comuna sincronizadas correctamente.")
            except Exception as seq_err:
                print(f"ℹ️ Nota sobre secuencias: {seq_err}")

        total_reg = db.query(Region).count()
        total_com = db.query(Comuna).count()
        print(f"📊 Totales en BD: {total_reg} Regiones, {total_com} Comunas.")

    except Exception as e:
        db.rollback()
        print(f"❌ Error durante el sembrado de geografía: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    seed_geografia()
