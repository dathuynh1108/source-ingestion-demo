FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN pip install --no-cache-dir uv

COPY pyproject.toml /app/pyproject.toml
COPY warehouse_chatserver /app/warehouse_chatserver
COPY main.py /app/main.py

RUN uv pip install --system .

EXPOSE 8001

CMD ["python", "main.py"]
