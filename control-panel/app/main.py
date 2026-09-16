import os
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from app.auth import router as auth_router
from app.killswitch import router as killswitch_router
from app.whitelist import router as whitelist_router
from app.audit import router as audit_router

app = FastAPI(
    title="Goose-in-the-Box Control Panel API",
    description="監査ダッシュボード + キルスイッチ + 通信制御 統合 API",
    version="2.0.0"
)

# Include API Routers
app.include_router(auth_router)
app.include_router(killswitch_router)
app.include_router(whitelist_router)
app.include_router(audit_router)

# Mount static files directory
STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
os.makedirs(STATIC_DIR, exist_ok=True)

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "control-panel"}

# Catch-all route to serve SPA index.html
@app.get("/{full_path:path}")
def serve_spa(full_path: str):
    # If file exists in static dir, serve it
    file_path = os.path.join(STATIC_DIR, full_path)
    if full_path and os.path.isfile(file_path):
        return FileResponse(file_path)
    
    # Fallback to index.html for SPA routing
    index_path = os.path.join(STATIC_DIR, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path)
    
    return JSONResponse(
        status_code=404,
        content={"detail": "Control Panel UI index.html not found"}
    )
