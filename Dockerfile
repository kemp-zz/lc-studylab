# ====================== 前端构建 – 基础镜像 ======================
FROM node:20-alpine AS frontend-base
WORKDIR /app/frontend

# 只拷贝依赖文件（用于缓存层）
COPY frontend/package*.json ./

# ① 先尝试 npm ci；若失败则 fallback 到 npm install
RUN npm ci --silent --no-audit --prefer-offline \
    || (echo "⚠️ npm ci 失败 → 使用 npm install" && npm install --silent --no-audit)

# 复制完整源码并构建
COPY frontend ./
RUN npm run build --silent

# 把产物统一放到 /out，后面的运行时阶段只会取这里的内容
RUN mkdir -p /out && cp -r .next /out/


# ====================== 后端构建 ======================
FROM python:3.11-slim-bookworm AS backend-builder
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt


# ====================== 运行时镜像 ======================
FROM python:3.11-slim-bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libpq5 tini && \
    rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/backend \
    PORT=8000 \
    STORAGE_DIR=/data \
    PATH=/root/.local/bin:$PATH

# 创建目录
RUN mkdir -p /app/backend /data /app/frontend
WORKDIR /app/backend

# 复制后端产物
COPY --from=backend-builder /root/.local /root/.local
COPY --from=backend-builder /app/backend /app/backend
COPY backend .

# 复制前端产物（前端构建阶段已经把 .next 放到 /out）
COPY --from=frontend-base /out/.next /app/frontend/.next

EXPOSE ${PORT}
HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost:${PORT}/health || exit 1

ENTRYPOINT ["tini", "--"]
CMD ["uvicorn", "api.http_server:app", "--host", "0.0.0.0", "--port", "${PORT}", "--workers", "4"]
