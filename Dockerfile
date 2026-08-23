FROM python:3.11-slim

# Установка необходимых инструментов для изоляции и логирования
RUN apt-get update && apt-get install -y --no-install-recommends \
    strace \
    iptables \
    npm \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace/
RUN pip install --upgrade pip && pip install -e .
CMD ["/bin/bash"]
