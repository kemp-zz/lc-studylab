# ====================== 第一阶段：前端构建 ======================
FROM node:20-alpine AS frontend-builder

# 安装前端依赖
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci --silent

# 构建前端
COPY frontend .
RUN npm run build

# ====================== 第二阶段：后端构建 ======================
FROM python:3.11-slim-bookworm AS backend-builder

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
    curl && \
    rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖
WORKDIR /app/backend
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ====================== 第三阶段：运行时镜像 ======================
FROM python:3.11-slim-bookworm

# 安装运行时依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libpq5 \
    tini && \
    rm -rf /var/lib/apt/lists/*

# 配置环境变量
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/backend \
    PORT=8000 \
    STORAGE_DIR=/data

# 创建目录结构
RUN mkdir -p /app/backend /data
WORKDIR /app/backend

# 从构建阶段复制文件
COPY --from=backend-builder /root/.local /root/.local
COPY --from=backend-builder /app/backend /app/backend
COPY --from=frontend-builder /app/frontend/.next /app/frontend/.next
COPY backend .

# 配置 Python 路径
ENV PATH=/root/.local/bin:$PATH

# 暴露端口
EXPOSE ${PORT}

# 设置入口点
ENTRYPOINT ["tini", "--"]
CMD ["uvicorn", "api.http_server:app", "--host", "0.0.0.0", "--port", "${PORT}"]

# ====================== 健康检查 ======================
HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost:${PORT}/health || exit 1
