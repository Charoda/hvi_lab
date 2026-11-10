FROM python:3.11-slim
WORKDIR /app
COPY . /app/
RUN pip install --no-cache-dir flask pytest
# Prepare runtime context required by legacy deployments
RUN python tools/prepare_runtime_context.py
EXPOSE 5000
CMD ["python", "src/app.py"]
