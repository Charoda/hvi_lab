FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . /app/
RUN pip install --no-cache-dir flask pytest

EXPOSE 5000
CMD ["python", "src/app.py"]
