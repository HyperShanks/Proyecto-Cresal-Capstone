import os
import re
import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import RedirectResponse, StreamingResponse
import requests

logger = logging.getLogger("cresal.updates")

router = APIRouter(prefix="/api/v1/updates", tags=["Actualizaciones de la App"])

# Configuración de GitHub Repository
GITHUB_OWNER = os.getenv("GITHUB_REPO_OWNER", "FelipeCSDav")
GITHUB_REPO = os.getenv("GITHUB_REPO_NAME", "CresalRepoCapstone")
GITHUB_TOKEN = os.getenv("GITHUB_RELEASE_TOKEN") or os.getenv("GITHUB_TOKEN")

def parse_version(v_str: str) -> tuple:
    """
    Convierte '1.0.1+2' o 'v1.0.1' en una tupla ordenable (1, 0, 1, 2).
    """
    if not v_str:
        return (0, 0, 0, 0)
    
    # Remover prefijo 'v' si existe
    cleaned = v_str.strip().lstrip("vV")
    # Separar parte semántica y build number (+n)
    parts = cleaned.split("+")
    version_part = parts[0]
    build_num = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    
    semver = [int(p) for p in re.findall(r"\d+", version_part)]
    while len(semver) < 3:
        semver.append(0)
        
    return (*semver[:3], build_num)


def get_latest_github_release() -> Optional[dict]:
    """
    Obtiene la información del último release desde la API de GitHub.
    Requiere GITHUB_TOKEN si el repositorio es privado.
    """
    if not GITHUB_TOKEN:
        logger.warning("No se ha configurado GITHUB_RELEASE_TOKEN o GITHUB_TOKEN. No es posible consultar GitHub Releases privados.")
        return None

    url = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest"
    headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Cresal-Backend-Updater"
    }

    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code == 200:
            return response.json()
        elif response.status_code == 404:
            logger.info("No se encontraron releases publicados en el repositorio.")
            return None
        else:
            logger.error(f"Error al consultar GitHub Releases: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        logger.error(f"Excepción al conectar con GitHub API: {str(e)}")
        return None


@router.get("/check")
def check_for_updates(
    current_version: str = Query(..., description="Versión actual de la app (ej: 1.0.0 o 1.0.0+1)"),
    platform: str = Query("android", description="Plataforma de la app ('android' o 'windows')")
):
    """
    Verifica si existe una versión más reciente disponible en GitHub Releases.
    """
    release = get_latest_github_release()
    
    if not release:
        return {
            "update_available": False,
            "latest_version": current_version,
            "release_notes": "",
            "download_url": None,
            "message": "No hay versiones remotas configuradas o repositorio sin releases."
        }

    tag_name = release.get("tag_name", "0.0.0")
    remote_version_str = tag_name.lstrip("vV")
    
    current_tuple = parse_version(current_version)
    remote_tuple = parse_version(remote_version_str)
    
    # Comparamos si la versión remota es estrictamente mayor que la versión actual
    is_newer = remote_tuple > current_tuple
    
    # Buscar asset según la plataforma
    assets = release.get("assets", [])
    target_asset = None
    
    platform_lower = platform.lower()
    for asset in assets:
        name = asset.get("name", "").lower()
        if platform_lower == "android" and name.endswith(".apk"):
            target_asset = asset
            break
        elif platform_lower == "windows" and (name.endswith(".exe") or name.endswith(".msi")):
            target_asset = asset
            break

    download_endpoint = None
    if target_asset:
        download_endpoint = f"/api/v1/updates/download/{platform_lower}"

    return {
        "update_available": is_newer and (target_asset is not None),
        "latest_version": remote_version_str,
        "release_name": release.get("name") or tag_name,
        "release_notes": release.get("body") or "Mejoras generales y correcciones de errores.",
        "published_at": release.get("published_at"),
        "download_url": download_endpoint,
        "asset_name": target_asset.get("name") if target_asset else None,
        "asset_size": target_asset.get("size") if target_asset else 0
    }


@router.get("/download/{platform}")
def download_update_asset(platform: str):
    """
    Descarga segura del archivo ejecutable o APK desde GitHub Releases privado.
    Genera una redirección temporal 302 autorizada o transmite el archivo.
    """
    if not GITHUB_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Servicio de actualización no configurado en el servidor (falta GITHUB_RELEASE_TOKEN)."
        )

    release = get_latest_github_release()
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No hay releases disponibles.")

    platform_lower = platform.lower()
    assets = release.get("assets", [])
    target_asset = None

    for asset in assets:
        name = asset.get("name", "").lower()
        if platform_lower == "android" and name.endswith(".apk"):
            target_asset = asset
            break
        elif platform_lower == "windows" and (name.endswith(".exe") or name.endswith(".msi")):
            target_asset = asset
            break

    if not target_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró un instalador para la plataforma '{platform}' en el release actual."
        )

    asset_id = target_asset.get("id")
    asset_url = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/assets/{asset_id}"
    
    headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/octet-stream",
        "User-Agent": "Cresal-Backend-Updater"
    }

    try:
        # GitHub responderá con 302 hacia un pre-signed S3 URL cuando enviamos Accept: application/octet-stream
        response = requests.get(asset_url, headers=headers, allow_redirects=False, timeout=10)
        
        if response.status_code in (301, 302) and "Location" in response.headers:
            # Redireccionar directamente al usuario a la descarga de alta velocidad de S3
            return RedirectResponse(url=response.headers["Location"], status_code=status.HTTP_302_FOUND)
        
        # En caso de que GitHub no redirija y devuelva el contenido directamente
        if response.status_code == 200:
            def iterfile():
                with requests.get(asset_url, headers=headers, stream=True, timeout=60) as r:
                    r.raise_for_status()
                    for chunk in r.iter_content(chunk_size=65536):
                        yield chunk

            return StreamingResponse(
                iterfile(),
                media_type="application/octet-stream",
                headers={"Content-Disposition": f"attachment; filename={target_asset.get('name')}"}
            )
            
        raise HTTPException(
            status_code=response.status_code,
            detail=f"GitHub API error al obtener asset: {response.text}"
        )
    except requests.exceptions.RequestException as e:
        logger.error(f"Error al descargar asset de GitHub: {str(e)}")
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Error de conexión con GitHub Releases.")
