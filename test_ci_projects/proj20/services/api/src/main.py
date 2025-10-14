"""
API service main application
"""
from fastapi import FastAPI

app = FastAPI(title="Monorepo Platform API", version="2.0.0")


@app.get("/")
async def root():
    return {"message": "API Service", "version": "2.0.0"}


@app.get("/health")
async def health():
    return {"status": "healthy"}
