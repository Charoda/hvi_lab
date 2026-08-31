#!/usr/bin/env bash
# Однократная настройка Docker для проброса NVIDIA GPU в контейнеры.
# Требует sudo. После успешного завершения:
#   docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
set -euo pipefail

if docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
    echo "[gpu] Docker уже видит GPU — ничего делать не нужно."
    exit 0
fi

if ! command -v nvidia-smi &>/dev/null; then
    echo "[gpu] ОШИБКА: nvidia-smi не найден — сначала установите драйвер NVIDIA." >&2
    exit 1
fi

echo "[gpu] Устанавливаю nvidia-container-toolkit..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

echo "[gpu] Проверка..."
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi -L
echo "[gpu] Готово."
