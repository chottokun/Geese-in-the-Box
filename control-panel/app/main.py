import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from app.auth import router as auth_router
from app.killswitch import router as killswitch_router
from app.whitelist import router as whitelist_router
from app.audit import router as audit_router
from app.temp_whitelist import temp_whitelist_watcher_loop, check_and_expire_temp_domains

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 起動時: 過去の期限切れドメインを直ちにクリーンアップ
    try:
        check_and_expire_temp_domains(reconfigure=True)
    except Exception as e:
        print(f"Startup temp whitelist check failed: {e}")

    # バックグラウンド監視タスク開始
    watcher_task = asyncio.create_task(temp_whitelist_watcher_loop())
    yield
    # 終了時: タスクキャンセル
    watcher_task.cancel()
    try:
        await watcher_task
    except asyncio.CancelledError:
        pass

app = FastAPI(
    title="Goose-in-the-Box Control Panel API",
    description="監査ダッシュボード + キルスイッチ + 通信制御 統合 API",
    version="2.1.0",
    lifespan=lifespan
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
