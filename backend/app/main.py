from fastapi import FastAPI

from app.api.routes import auth

app = FastAPI(
    title="Some Journey API",
    version="0.1.0",
)

app.include_router(auth.router)


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}
