FROM python:3.11-slim

WORKDIR /app

COPY server.py /app/server.py
COPY 15Flask/day04 /app/15Flask/day04

RUN pip install --no-cache-dir flask

EXPOSE 5000

CMD ["python", "server.py"]
