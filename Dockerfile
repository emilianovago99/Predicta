FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --create-home predicta
COPY main.py settings.py database.py security.py migrate.py admin.py notifications.py device_setup.py simulador_edge.py simulador_cambio.py ./
COPY migrations/ ./migrations/
USER predicta
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
