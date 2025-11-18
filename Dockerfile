# ====================== 前端构建 – 基础镜像 ======================
FROM node:20-alpine AS frontend-base
WORKDIR /app/frontend

# ------- 只拷贝依赖文件（缓存层） -------
COPY frontend/package*.json ./

# ======== ① 尝试使用 npm ci（必须有完整 lock） ========
FROM frontend-base AS frontend-ci
# 若 lock 文件缺失或损坏，下面一步会直接失败 → 进入 fallback
RUN npm ci --silent --no-audit --prefer-offline || \
    (echo "⚠️ npm ci 失败，切换到 npm install" && exit 1)

# ======== ② fallback：npm install（没有 lock 时使用） ========
FROM frontend-base AS frontend-install
RUN npm install --silent --no-audit

# ======== 统一后继续构建 ========
# 这里用 `${BUILD_STAGE}` 参数决定走哪条路径（在 CI 中传递）  
ARG BUILD_STAGE=ci
FROM frontend-${BUILD_STAGE} AS frontend-build
COPY frontend ./
RUN npm run build --silent

# 把产物统一拷贝到 /out 目录，后面的运行时阶段直接引用
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

# 复制前端产物（默认走 ci；若 CI 中传 BUILD_STAGE=install 则走 fallback）
COPY --from=frontend-build /out/.next /app/frontend/.next

EXPOSE ${PORT}
HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost:${PORT}/health || exit 1

ENTRYPOINT ["tini", "--"]
CMD ["uvicorn", "api.http_server:app", "--host", "0.0.0.0", "--port", "${PORT}", "--workers", "4"]
