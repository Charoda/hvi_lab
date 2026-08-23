#!/usr/bin/env python3
import subprocess
import os
import sys
import json
import glob

chain_id = os.environ.get('CHAIN_ID')
if not chain_id:
    print("Ошибка: CHAIN_ID не задан")
    sys.exit(1)

chain_path = f"/workspace/benchmark/chains/{chain_id}"
substrate_base = "/workspace/benchmark/apps"

print(f"==> Цепочка: {chain_id}")
print(f"==> Поиск субстратов в: {substrate_base}")

# Проверяем, что папка существует
if not os.path.exists(substrate_base):
    print(f"Ошибка: папка {substrate_base} не существует!")
    sys.exit(1)

# 1. Читаем substrate_id из chain.json
try:
    with open(f"{chain_path}/chain.json", 'r') as f:
        chain_data = json.load(f)
        substrate_id = chain_data.get('substrate_id')
        print(f"Субстрат по chain.json: {substrate_id}")
except Exception as e:
    print(f"Ошибка чтения chain.json: {e}")
    sys.exit(1)

# 2. Ищем папку субстрата несколькими способами
substrate_path = None

# Способ 1: Поиск с префиксом task_ и любым окончанием, содержащим substrate_id
for d in glob.glob(f"{substrate_base}/task_*{substrate_id}*"):
    substrate_path = d
    break

# Способ 2: Поиск по содержимому (если substrate_id внутри названия)
if not substrate_path:
    for d in os.listdir(substrate_base):
        full_path = os.path.join(substrate_base, d)
        if os.path.isdir(full_path) and substrate_id in d:
            substrate_path = full_path
            break

# Способ 3: Поиск по всем папкам в apps
if not substrate_path:
    print("Пробуем найти субстрат по всем папкам...")
    for d in os.listdir(substrate_base):
        full_path = os.path.join(substrate_base, d)
        if os.path.isdir(full_path):
            # Проверяем, есть ли внутри папка с именем, содержащим substrate_id
            for sub in os.listdir(full_path):
                sub_full = os.path.join(full_path, sub)
                if os.path.isdir(sub_full) and substrate_id in sub:
                    substrate_path = sub_full
                    break
            if substrate_path:
                break

if not substrate_path:
    print(f"Субстрат '{substrate_id}' не найден в {substrate_base}")
    print("Доступные папки:")
    for d in sorted(os.listdir(substrate_base)):
        print(f"  - {d}")
    sys.exit(1)

print(f"Найденный путь к субстрату: {substrate_path}")

# 3. Применяем эталонное решение
golden_solution = f"{chain_path}/golden_solution.sh"
if not os.path.exists(golden_solution):
    print(f"Не найден {golden_solution}")
    sys.exit(1)

print(f"==> Применяем эталонное решение...")
result = subprocess.run(
    ["bash", golden_solution],
    cwd=substrate_path,
    capture_output=True,
    text=True
)
if result.stdout:
    print(result.stdout)
if result.stderr:
    print("STDERR:", result.stderr)

# 4. Запускаем оракул
poc_files = glob.glob(f"{chain_path}/poc_*.py")
if not poc_files:
    print("Не найден poc_*.py скрипт")
    sys.exit(1)

poc_script = poc_files[0]
print(f"==> Запускаем оракул: {os.path.basename(poc_script)}")

result = subprocess.run(
    ["python3", poc_script],
    cwd=substrate_path,
    capture_output=True,
    text=True
)

if result.stdout:
    print(result.stdout)
if result.stderr:
    print("STDERR:", result.stderr)

# 5. Определяем результат
output = result.stdout + result.stderr
if "VULNERABLE" in output.upper():
    print("✅ РЕЗУЛЬТАТ: VULNERABLE")
    sys.exit(0)
elif "SECURE" in output.upper():
    print("✅ РЕЗУЛЬТАТ: SECURE")
    sys.exit(0)
else:
    print("❌ НЕИЗВЕСТНЫЙ РЕЗУЛЬТАТ")
    print("--- Полный вывод оракула ---")
    print(output)
    sys.exit(1)
