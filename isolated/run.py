#!/usr/bin/env python3
"""Изолированный запуск сценария MOSAIC-Bench.

Одна команда поднимает СВЕЖЕЕ изолированное окружение под цепочку:

    docker-сеть (исходящий трафик заблокирован по умолчанию)
    + контейнеры сервисов приложения (Mongo / Postgres / Mailhog ...)
    + контейнер приложения (собственный Dockerfile субстрата)
    + контейнер-актор (стратего: эталонное решение; в будущем — AI-агент),
      работающий под strace + inotifywait, БЕЗ доступа к ФС хоста

и после прогона сносит всё, кроме артефактов в logs/<run_id>/.

Использование:
    python3 isolated/run.py <chain_id> [--network blocked|allowlist|open]
                            [--timeout 600] [--keep] [--verbose]
    python3 isolated/run.py --cleanup          # убрать все хвосты прошлых запусков

Схема изоляции:
  ФС        — актор получает копию дерева задач через `docker cp` до старта;
              с хоста смонтирован только каталог артефактов (/evidence) и
              каталог цепочки (read-only).
  Сеть      — режимы:
              blocked   (по умолчанию): сеть `--internal` — исходящий трафик
                        запрещён на уровне ядра, контейнеры прогона видят
                        только друг друга;
              allowlist : обычная сеть + iptables в контейнере-акторе
                        (белый список доменов, см. allowlist.sh);
              open      : обычная сеть без ограничений (контроль).
  Метрика   — системные вызовы актора пишутся в logs/<run_id>/strace.log,
              события ФС — в inotify.log (схема из песочницы MalSkillBench).

Скрипт намеренно использует только стандартную библиотеку и переиспользует
реестр приложений `mosaic.deploy.ABC_BENCH_APPS` (порты, сервисы, переменные
окружения, health-эндпоинты), чтобы не дублировать то, что уже работает.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from mosaic.deploy import ABC_BENCH_APPS  # noqa: E402  (после настройки sys.path)

LABEL_KEY = "mosaic.iso.run"
AGENT_IMAGE_NAME = "mosaic-iso-agent"
APP_IMAGE_PREFIX = "mosaic-iso-app"
NETWORK_PREFIX = "mosaic-iso-net"
LOG_ROOT = REPO_ROOT / "logs"

# Тег образа песочницы привязан к содержимому файлов, из которых он собран:
# изменение любого из них автоматически даёт новый тег и пересборку.
_AGENT_FILES = ("Dockerfile.agent", "entrypoint.sh", "allowlist.sh",
                "honey_listener.py", "poc_runner.py", "llama_tool_proxy.py")


def agent_image_tag() -> str:
    h = hashlib.sha256()
    for name in _AGENT_FILES:
        h.update((REPO_ROOT / "isolated" / name).read_bytes())
    return f"{AGENT_IMAGE_NAME}:{h.hexdigest()[:12]}"


AGENT_IMAGE = agent_image_tag()

# Файлы, изменение которых требует пересборки образа приложения
# (копирование в работающий контейнер новые зависимости не установит).
DEP_FILE_GLOBS = ("requirements.txt", "package.json", "yarn.lock", "Pipfile", "Dockerfile")

# WorkingDir контейнера не всегда совпадает с корнем дерева приложения:
# у монорепозиториев WORKDIR указывает на подпроект (например,
# /app/nodejs/express-multer при корне дерева в /app). Здесь задаётся,
# КУДА класть содержимое app_dir внутри контейнера.
APP_ROOT_OVERRIDES = {
    "task_attacomsian_code_examples__file_upload_apis": "/app",
}


# ---------------------------------------------------------------------------
# Подключение реального агента (сейчас: Qwen Code CLI)
# ---------------------------------------------------------------------------

QWEN_SETTINGS_PATH = Path.home() / ".qwen" / "settings.json"

# Ключи настроек хоста, которые действительно нужны агенту в песочнице
# (всё остальное — история/кастомизации хоста — внутрь не копируется).
QWEN_SETTINGS_PICK = ("env", "modelProviders", "model", "security", "$version")

# Локальный бэкенд llama.cpp: сервер поднимается прямо в контейнере-акторе
# (entrypoint.sh запускает `llama-server` при LLAMA_START=1), а веса модели
# (GGUF) запечены в образ при сборке (Dockerfile.agent берёт файл из
# контекста isolated/models/). Не зависит от внешних API-ключей и работает
# при любом режиме сети, включая blocked (см. docs/ISOLATED_RUN.md, раздел 11).
LLAMA_BASE_URL = "http://127.0.0.1:11434/v1"
MODELS_DIR = REPO_ROOT / "isolated" / "models"
DEFAULT_LLAMA_MODEL_FILE = "qwen2.5-coder-7b-instruct-q4_k_m.gguf"


def llama_alias(name: str) -> str:
    """Имя модели для OpenAI API (--alias llama-server) — из имени .gguf."""
    name = name.rstrip("/").rsplit("/", 1)[-1]
    return name[:-5] if name.endswith(".gguf") else name


DEFAULT_LLAMA_MODEL = llama_alias(DEFAULT_LLAMA_MODEL_FILE)


def baked_llama_model() -> str | None:
    """Модель, запечённая в образ песочницы (маркер из Dockerfile.agent)."""
    r = docker("run", "--rm", "--entrypoint", "cat", AGENT_IMAGE,
               "/opt/iso/LLAMA_MODEL", check=False, timeout=120)
    if r.returncode != 0:
        return None
    return (r.stdout or "").strip() or None


def qwen_host_settings() -> dict:
    if not QWEN_SETTINGS_PATH.is_file():
        raise SystemExit(
            f"Не найден {QWEN_SETTINGS_PATH} — Qwen CLI на хосте не настроен "
            f"(см. docs/ISOLATED_RUN.md, раздел 11).")
    return json.loads(QWEN_SETTINGS_PATH.read_text())


def qwen_llm_domain(settings: dict) -> str | None:
    url = (settings.get("model") or {}).get("baseUrl") or ""
    m = re.match(r"https?://([^/]+)", url)
    return m.group(1) if m else None


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f"[iso] {msg}", flush=True)


def run(cmd: list[str], *, check: bool = True, capture: bool = True,
        timeout: int | None = 900) -> subprocess.CompletedProcess:
    """Обёртка над subprocess: печатает команду в режиме --verbose."""
    if VERBOSE:
        log("$ " + " ".join(cmd))
    r = subprocess.run(cmd, capture_output=capture, text=True, timeout=timeout)
    if check and r.returncode != 0:
        out = (r.stdout or "") + (r.stderr or "")
        raise RuntimeError(f"команда завершилась с кодом {r.returncode}: "
                           f"{' '.join(cmd[:6])}...\n{out[-3000:]}")
    return r


def docker(*args: str, check: bool = True, timeout: int | None = 900) -> subprocess.CompletedProcess:
    return run(["docker", *args], check=check, timeout=timeout)


def image_exists(tag: str) -> bool:
    r = docker("images", "-q", tag, check=False)
    return bool(r.stdout.strip())


def container_running(name: str) -> bool:
    r = docker("ps", "-q", "--filter", f"name=^{name}$", check=False)
    return bool(r.stdout.strip())


def wait_http_inside_net(net_name: str, url: str, *, timeout_s: int = 120,
                         what: str = "") -> bool:
    """Ждёт ответа сервера САЙДКАРОМ внутри изолированной сети (в сети
    --internal порты на хост не публикуются, поэтому хост достучаться не
    может). Любой статус < 500 считается здоровым (4xx = сервер жив, просто
    нет маршрута — как в mosaic.deploy)."""
    probe = (
        "end=$((SECONDS+{t})); "
        "while [ $SECONDS -lt $end ]; do "
        "  code=$(curl -s -o /dev/null -w '%{{http_code}}' --max-time 3 '{u}' 2>/dev/null); "
        "  if [ -n \"$code\" ] && [ \"$code\" -ge 100 ] && [ \"$code\" -lt 500 ]; then exit 0; fi; "
        "  sleep 2; "
        "done; exit 1"
    ).format(t=timeout_s, u=url)
    r = docker("run", "--rm", "--entrypoint", "bash", "--network", net_name, AGENT_IMAGE,
               "-c", probe, check=False, timeout=timeout_s + 60)
    if r.returncode != 0 and what:
        log(f"не дождался: {what} ({url})")
    return r.returncode == 0


def tail_container_logs(container: str, tail: int = 60) -> None:
    r = docker("logs", "--tail", str(tail), container, check=False, timeout=30)
    text = ((r.stdout or "") + (r.stderr or "")).strip()
    if text:
        log(f"последние логи {container}:\n{text[-3000:]}")


def file_hashes(root: Path) -> dict[str, str]:
    """Хэши файлов зависимостей внутри дерева (для решения: перезапуск или пересборка)."""
    out: dict[str, str] = {}
    for pat in DEP_FILE_GLOBS:
        for p in sorted(root.rglob(pat)):
            if p.is_file() and ".git" not in p.parts and "node_modules" not in p.parts:
                out[str(p.relative_to(root))] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


# ---------------------------------------------------------------------------
# Оркестратор прогона
# ---------------------------------------------------------------------------

class IsolatedRun:
    def __init__(self, chain_id: str, network_mode: str, timeout_s: int, keep: bool,
                 actor: str = "golden", llm: str = "llama",
                 llama_model_file: str = DEFAULT_LLAMA_MODEL_FILE):
        self.chain_id = chain_id
        self.network_mode = network_mode
        self.timeout_s = timeout_s
        self.keep = keep
        self.actor = actor
        self.llm = llm
        self.llama_model_file = Path(llama_model_file).name
        self.llama_model = llama_alias(llama_model_file)
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.run_id = f"{chain_id}-{ts}"
        self.label = f"{LABEL_KEY}={self.run_id}"
        self.net_name = f"{NETWORK_PREFIX}-{self.run_id}"
        self.log_dir = LOG_ROOT / self.run_id
        self.containers: list[str] = []          # в порядке создания
        self._torn_down = False

        self.chain_dir = REPO_ROOT / "benchmark" / "chains" / chain_id
        chain_json = self.chain_dir / "chain.json"
        if not chain_json.is_file():
            raise SystemExit(f"Цепочка не найдена: {chain_json}\n"
                             f"Список цепочек: ls {REPO_ROOT / 'benchmark' / 'chains'}")
        self.chain_meta = json.loads(chain_json.read_text())
        self.task_id: str = self.chain_meta["task_id"]
        self.poc_module: str = self.chain_meta.get("poc_module", "")

        cfg = ABC_BENCH_APPS.get(self.task_id)
        if cfg is None:
            raise SystemExit(f"Задача '{self.task_id}' отсутствует в ABC_BENCH_APPS "
                             f"(mosaic/deploy.py) — субстрат не поддерживается.")
        if cfg.go_binary or cfg.hot_swap_strategy != "copy_restart":
            raise SystemExit(f"Задача '{self.task_id}' использует особую схему деплоя "
                             f"(Go-сборка / пересборка образа) и пока не поддерживается "
                             f"изолированным запуском. Возьмите цепочку на другом субстрате.")
        self.cfg = cfg
        self.task_dir = REPO_ROOT / "benchmark" / "apps" / self.task_id
        self.app_src = self.task_dir / cfg.app_dir
        if not (self.app_src / "Dockerfile").is_file():
            raise SystemExit(f"В {self.app_src} нет Dockerfile — не из чего собрать приложение.")
        self.app_container = f"iso-{self.run_id}-app"
        self.actor_container = f"iso-{self.run_id}-actor"

    # --- жизненный цикл -----------------------------------------------------

    def teardown(self) -> None:
        if self._torn_down:
            return
        self._torn_down = True
        if self.keep:
            log(f"--keep: окружение НЕ удалено. Контейнеры: {', '.join(self.containers)}, "
                f"сеть: {self.net_name}")
            return
        log("сношу окружение прогона...")
        for name in reversed(self.containers):
            docker("rm", "-f", name, check=False, timeout=60)
        docker("network", "rm", self.net_name, check=False, timeout=60)
        # Проверка чистоты: после прогона не должно остаться ничего с нашим лейблом.
        leftover = docker("ps", "-aq", "--filter", f"label={self.label}",
                          check=False).stdout.strip()
        net_left = docker("network", "ls", "-q", "--filter", f"name=^{self.net_name}$",
                          check=False).stdout.strip()
        if leftover or net_left:
            log(f"ВНИМАНИЕ: остались хвосты (контейнеры: {leftover!r}, сеть: {net_left!r})")
        else:
            log("чисто: контейнеров и сетей прогона не осталось")

    def _register_signals(self) -> None:
        def _handler(signum, _frame):
            log(f"получен сигнал {signum}, очищаю окружение...")
            self.teardown()
            sys.exit(128 + signum)
        signal.signal(signal.SIGINT, _handler)
        signal.signal(signal.SIGTERM, _handler)

    # --- шаги ---------------------------------------------------------------

    def build_images(self) -> None:
        if image_exists(AGENT_IMAGE):
            log(f"образ песочницы уже есть: {AGENT_IMAGE}")
        else:
            log("собираю образ песочницы (однократно; первая сборка долгая — "
                "скачиваются бинарник llama.cpp и контекст с весами (GGUF), "
                "~5 ГБ)...")
            if self.actor == "qwen" and self.llm == "llama":
                model_path = MODELS_DIR / self.llama_model_file
                if not model_path.is_file():
                    raise SystemExit(
                        f"Веса модели не найдены: {model_path}\n"
                        f"Скачайте их с докачкой: "
                        f"bash isolated/models/download.sh <URL .gguf>")
            build_args: list[str] = []
            # Если запрошена не модель по умолчанию, запекаем её (тег образа
            # считается от файлов, поэтому маркер /opt/iso/LLAMA_MODEL —
            # единственный источник правды о запечённой модели).
            if (self.actor == "qwen" and self.llm == "llama"
                    and self.llama_model_file != DEFAULT_LLAMA_MODEL_FILE):
                build_args = ["--build-arg", f"LLAMA_MODEL_FILE={self.llama_model_file}",
                              "--build-arg", f"LLAMA_MODEL_ALIAS={self.llama_model}"]
            docker("build", *build_args,
                   "-f", str(REPO_ROOT / "isolated" / "Dockerfile.agent"),
                   "-t", AGENT_IMAGE, str(REPO_ROOT / "isolated"), timeout=3600)

        self.app_image = f"{APP_IMAGE_PREFIX}-{self.task_id}:latest"
        if image_exists(self.app_image):
            log(f"образ приложения уже есть: {self.app_image}")
        else:
            log(f"собираю образ приложения из {self.app_src} (однократно)...")
            r = docker("build", "-t", self.app_image, str(self.app_src),
                       check=False, timeout=1800)
            if r.returncode != 0:
                log((r.stdout or "")[-2000:])
                log((r.stderr or "")[-2000:])
                raise RuntimeError("не удалось собрать образ приложения")

    def create_network(self) -> None:
        args = ["network", "create"]
        if self.network_mode == "blocked":
            args += ["--internal"]  # исходящий трафик запрещён на уровне ядра
        args += [self.net_name]
        docker(*args)
        log(f"сеть: {self.net_name} (режим: {self.network_mode})")

    def start_services(self) -> None:
        for svc in self.cfg.services:
            name = f"iso-{self.run_id}-{svc.name}"
            args = ["run", "-d", "--name", name, "--network", self.net_name,
                    "--label", self.label]
            for t in svc.tmpfs:
                args += ["--tmpfs", t]
            for k, v in svc.env.items():
                args += ["-e", f"{k}={v}"]
            args += [svc.image]
            docker(*args)
            self.containers.append(name)
            log(f"сервис: {svc.name} ({svc.image}) -> {name}")
            if svc.init_cmd:
                self._wait_service_init(name, svc.init_cmd)

    def _wait_service_init(self, name: str, init_cmd: str) -> None:
        for attempt in range(60):
            r = docker("exec", name, "bash", "-lc", init_cmd, check=False, timeout=30)
            if r.returncode == 0:
                return
            if not container_running(name):
                raise RuntimeError(f"сервис {name} умер до инициализации")
            time.sleep(1)
        raise RuntimeError(f"сервис {name} не инициализировался за 60с: {init_cmd}")

    def _app_env(self) -> dict[str, str]:
        env = {}
        for k, v in self.cfg.env.items():
            for svc in self.cfg.services:
                v = v.replace("{{" + svc.name + "}}", f"iso-{self.run_id}-{svc.name}")
            env[k] = v
        return env

    def start_app(self, image: str) -> None:
        args = ["run", "-d", "--name", self.app_container, "--network", self.net_name,
                "--label", self.label]
        for k, v in self._app_env().items():
            args += ["-e", f"{k}={v}"]
        args += [image]
        docker(*args)
        self.containers.append(self.app_container)
        log(f"приложение: {image} -> {self.app_container} "
            f"(внутри сети: {self.cfg.app_port}/tcp)")

    def _app_url(self) -> str:
        return f"http://{self.app_container}:{self.cfg.app_port}{self.cfg.health_endpoint}"

    def wait_app_healthy(self, *, restart_on_fail: bool = True) -> bool:
        if wait_http_inside_net(self.net_name, self._app_url(),
                                timeout_s=max(self.cfg.health_timeout_s, 60),
                                what="приложение"):
            return True
        if restart_on_fail:
            tail_container_logs(self.app_container)
            log("приложение не поднялось с первого раза — перезапускаю и жду ещё раз")
            docker("restart", "-t", "2", self.app_container, check=False)
            time.sleep(2)
            return wait_http_inside_net(self.net_name, self._app_url(),
                                        timeout_s=max(self.cfg.health_timeout_s, 60),
                                        what="приложение после перезапуска")
        return False

    def run_actor(self) -> int:
        """Актор в песочнице: рабочая копия дерева задач копируется внутрь ДО
        старта (никаких монтирований ФС хоста на запись)."""
        # Конвенция MOSAIC (см. scripts/composition_curve.py): эталонные
        # скрипты выполняются с APP_DIR = каталог приложения в репозитории.
        app_dir_in_sandbox = f"/workspace/app/{self.cfg.app_dir}"
        extra_env: dict[str, str] = {}

        if self.actor == "qwen":
            prompt_file = self.chain_dir / "agent_prompt.txt"
            if not prompt_file.is_file():
                raise SystemExit(f"Для --actor qwen нужен файл промпта: {prompt_file}")
            extra_env["AGENT_PROMPT"] = prompt_file.read_text().strip()
            if self.llm == "llama":
                # Локальная модель: llama-server поднимается прямо в этом
                # контейнере (entrypoint.sh, LLAMA_START=1), веса (GGUF)
                # запечены в образ. LLM доступен при любом режиме сети,
                # включая blocked (никаких доменов в белый список добавлять
                # не надо).
                extra_env["LLAMA_START"] = "1"
                log(f"агент: LLM = llama.cpp внутри песочницы ({self.llama_model})")
            else:
                # Внешний API: домен провайдера из настроек хоста — в белый
                # список (см. allowlist.sh).
                domain = qwen_llm_domain(qwen_host_settings())
                if domain:
                    extra_env["EXTRA_DOMAINS"] = domain
                    log(f"агент: домен LLM-провайдера добавлен в белый список: {domain}")
            extra_env["QWEN_TELEMETRY_ENABLED"] = "false"
            extra_env["QWEN_CODE_SUPPRESS_YOLO_WARNING"] = "1"
            # Локальный инференс медленный: промпт первого запроса (~16 тыс.
            # токенов, системный + схемы всех инструментов) обрабатывается
            # минутами, и дефолтный стрим-таймаут CLI (240 с простоя) убивал
            # запрос, после чего агент деградировал в одноходовый режим.
            # 0 = снять лимит простоя стрима; общий потолок по-прежнему
            # ограничен снаружи (таймаут актора в песочнице).
            extra_env["QWEN_STREAM_IDLE_TIMEOUT_MS"] = "0"
            extra_env["QWEN_CODE_API_TIMEOUT_MS"] = "3600000"
            actor_cmd = (
                "mkdir -p /root/.qwen && "
                "mv /tmp/qwen-settings.json /root/.qwen/settings.json && "
                f"cd {app_dir_in_sandbox} && "
                "qwen --approval-mode yolo --safe-mode -o text -p \"$AGENT_PROMPT\""
            )
            log("актор: реальный агент (Qwen Code CLI, approval-mode=yolo, safe-mode)")
        else:
            stage_scripts = [self.chain_dir / f"golden_stage{i}.sh" for i in (1, 2, 3)]
            if all(p.is_file() for p in stage_scripts):
                actor_cmd = " && ".join(
                    f"bash /chain/golden_stage{i}.sh {app_dir_in_sandbox}"
                    for i in (1, 2, 3))
            else:
                actor_cmd = f"bash /chain/golden_solution.sh {app_dir_in_sandbox}"
            log(f"актор: эталонное решение {self.chain_meta.get('golden_solution', '')}")

        args = ["create", "--name", self.actor_container, "--network", self.net_name,
                "--label", self.label]
        args += ["-e", f"ACTOR_CMD={actor_cmd}",
                 "-e", f"EXEC_TIMEOUT={self.timeout_s}",
                 "-e", f"NETWORK_MODE={self.network_mode}",
                 "-e", "EVIDENCE_DIR=/evidence"]
        for k, v in extra_env.items():
            args += ["-e", f"{k}={v}"]
        # Необязательные переменные окружения сценария (например,
        # {"HONEY_PORT": "8080"} для сценариев на поведение агента).
        for k, v in (self.chain_meta.get("sandbox_env") or {}).items():
            args += ["-e", f"{k}={v}"]
        args += ["-v", f"{self.log_dir}:/evidence",
                 "-v", f"{self.chain_dir}:/chain:ro"]
        if self.network_mode == "allowlist":
            args += ["--cap-add", "NET_ADMIN"]  # нужен для iptables в allowlist.sh
        args += [AGENT_IMAGE]
        docker(*args)
        self.containers.append(self.actor_container)

        log("копирую дерево задачи в песочницу (изолированная ФС)...")
        docker("cp", f"{self.task_dir}/.", f"{self.actor_container}:/workspace/app")

        if self.actor == "qwen":
            self._inject_qwen_credentials()

        try:
            r = run(["docker", "start", "-a", self.actor_container],
                    timeout=self.timeout_s + 180)
            rc = r.returncode
        except subprocess.TimeoutExpired:
            docker("kill", self.actor_container, check=False)
            log("актор превысил лимит времени — контейнер убит")
            rc = 124
        return rc

    def _build_qwen_settings(self) -> dict:
        """Настройки Qwen CLI для контейнера-актора под выбранный бэкенд LLM."""
        if self.llm == "llama":
            # OpenAI-совместимый провайдер -> llama-server внутри этого же
            # контейнера (см. LLAMA_START в entrypoint.sh).
            # Ключ условный: локальной модели аутентификация не нужна
            # (--api-key в entrypoint.sh), внешние API-ключи в контейнер
            # не попадают вовсе.
            settings: dict = {
                "env": {
                    "OPENAI_API_KEY": "not-needed",
                    "OPENAI_BASE_URL": LLAMA_BASE_URL,
                    "OPENAI_MODEL": self.llama_model,
                },
                "modelProviders": {
                    "openai": [{
                        "id": self.llama_model,
                        "name": f"{self.llama_model} (llama.cpp, локально)",
                        "baseUrl": LLAMA_BASE_URL,
                        "envKey": "OPENAI_API_KEY",
                    }],
                },
                "security": {"auth": {"selectedType": "openai"}},
                "model": {"name": self.llama_model, "baseUrl": LLAMA_BASE_URL},
                "$version": 4,
            }
        else:
            host = qwen_host_settings()
            settings = {k: host[k] for k in QWEN_SETTINGS_PICK if k in host}
        settings["ui"] = {"autoModeAcknowledged": True}
        settings["telemetry"] = {"enabled": False}
        settings["tools"] = {"approvalMode": "yolo"}
        security = dict(settings.get("security") or {})
        security["folderTrust"] = {"enabled": False}
        settings["security"] = security
        return settings

    def _inject_qwen_credentials(self) -> None:
        """Копирует МИНИМАЛЬНЫЕ настройки Qwen CLI внутрь контейнера до старта.
        Агенту нужен доступ к LLM (локальный llama-server в этом же контейнере
        или внешний API), но живые монтирования ФС хоста в песочницу не
        допускаются: файл копируется разово (docker cp) и живёт только внутри
        контейнера прогона."""
        minimal = self._build_qwen_settings()
        with tempfile.TemporaryDirectory(prefix="mosaic_iso_qwen_") as tmp:
            src = Path(tmp) / "settings.json"
            src.write_text(json.dumps(minimal, ensure_ascii=False))
            # docker cp не создаёт отсутствующий каталог назначения, поэтому
            # файл кладётся в /tmp контейнера и переносится командой актора.
            docker("cp", str(src), f"{self.actor_container}:/tmp/qwen-settings.json")
        backend = (f"локальный llama.cpp, модель {self.llama_model}"
                   if self.llm == "llama" else "внешний API из настроек хоста")
        log(f"агент: настройки Qwen CLI ({backend}) скопированы в контейнер")

    def redeploy_app(self) -> str:
        """Доставляем изменения актора в контейнер приложения.
        Возвращает применённую стратегию: copy_restart | rebuild."""
        with tempfile.TemporaryDirectory(prefix="mosaic_iso_") as tmp:
            out = Path(tmp) / "app"
            out.mkdir()
            docker("cp", f"{self.actor_container}:/workspace/app/{self.cfg.app_dir}/.",
                   str(out))

            before = file_hashes(self.app_src)
            after = file_hashes(out)
            dep_changed = before != after

            workdir = docker("inspect", "--format", "{{.Config.WorkingDir}}",
                             self.app_container).stdout.strip() or "/"
            app_root = APP_ROOT_OVERRIDES.get(self.task_id, workdir)

            if not dep_changed:
                log(f"зависимости не менялись — копирую код в работающий контейнер ({app_root})")
                escaped = app_root.replace(" ", r"\ ")
                # Чистим старые файлы КРОМЕ установленных зависимостей.
                # В монорепозиториях зависимости могут лежать во вложенных
                # каталогах, поэтому каталоги удаляются только пустые.
                docker("exec", "--user", "0", self.app_container, "sh", "-c",
                       f"find {escaped} -mindepth 1 -type f "
                       f"-not -path '*/node_modules/*' "
                       f"-not -path '*/.venv/*' -delete; "
                       f"find {escaped} -mindepth 1 -depth -type d -empty -delete")
                docker("cp", f"{out}/.", f"{self.app_container}:{app_root}/")
                docker("restart", "-t", "2", self.app_container)
                return "copy_restart"

            log("изменились зависимости/Dockerfile — пересобираю образ приложения")
            layered = Path(tmp) / "Dockerfile"

            # Ставим только те файлы зависимостей, которые реально
            # добавились/изменились (в репозиториях встречаются «мусорные»
            # requirements.txt от обучающих примеров — их установка падает).
            changed = [p for p, h in after.items() if before.get(p) != h]
            changed_reqs = [p for p in changed if p.endswith("requirements.txt")]
            pkg_changed = any(p.endswith(("package.json", "yarn.lock")) for p in changed)

            dep_instructions: list[str] = []
            for req in changed_reqs:
                dep_instructions.append(
                    f"RUN pip3 install --no-cache-dir -r {app_root}/{req} "
                    f"|| echo 'WARN: не установился {req}'")
            if pkg_changed:
                dep_instructions.append(
                    f"RUN cd {app_root} && if [ -f package.json ]; then "
                    f"(yarn install --production --frozen-lockfile 2>/dev/null "
                    f"|| yarn install --production 2>/dev/null "
                    f"|| npm install --omit=dev || true); fi")
            dep_instructions.append(
                f"RUN if id -u node >/dev/null 2>&1; then chown -R node:node {app_root} || true; fi")
            layered.write_text(
                f"FROM {self.app_image}\n"
                f"COPY . {app_root}/\n"
                + "\n".join(dep_instructions) + "\n"
            )
            rebuilt = f"{APP_IMAGE_PREFIX}-{self.task_id}:iso-{self.run_id}"
            docker("build", "-f", str(layered), "-t", rebuilt, str(out), timeout=1800)

            # Пересоздаём контейнер приложения на той же сети
            docker("rm", "-f", self.app_container, check=False)
            self.containers.remove(self.app_container)
            self.start_app(rebuilt)
            return "rebuild"

    def run_oracle(self) -> tuple[str, str]:
        """PoC-оракул сайдкаром на изолированной сети: обращение к приложению
        по имени контейнера, исходящий трафик не требуется."""
        if not self.poc_module:
            return "NO_ORACLE", "в chain.json не указан poc_module"
        target_url = f"http://{self.app_container}:{self.cfg.app_port}"
        poc_container = f"iso-{self.run_id}-poc"
        r = docker("run", "--rm", "--entrypoint", "python3",
                   "--name", poc_container,
                   "--network", self.net_name, "--label", self.label,
                   "-v", f"{REPO_ROOT}:/repo:ro",
                   "-v", f"{self.log_dir}:/evidence",
                   "-e", f"POC_MODULE={self.poc_module}",
                   "-e", f"TARGET_URL={target_url}",
                   "-e", "REPO_DIR=/repo",
                   "-e", "EVIDENCE_DIR=/evidence",
                   "-w", "/repo",
                   AGENT_IMAGE, "/repo/isolated/poc_runner.py",
                   check=False, timeout=600)
        (self.log_dir / "poc_container.log").write_text(
            (r.stdout or "") + "\n--- stderr ---\n" + (r.stderr or ""))
        result_file = self.log_dir / "poc_result.json"
        if not result_file.is_file():
            return "ERROR", "оракул не оставил результат (см. вывод контейнера)"
        data = json.loads(result_file.read_text())
        return data.get("verdict", "ERROR"), data.get("evidence") or data.get("error", "")

    # --- прогон -------------------------------------------------------------

    def execute(self) -> dict:
        started = time.time()
        self._register_signals()
        self.log_dir.mkdir(parents=True, exist_ok=True)
        manifest = {
            "run_id": self.run_id,
            "chain_id": self.chain_id,
            "task_id": self.task_id,
            "actor": self.actor,
            "llm_backend": self.llm if self.actor == "qwen" else None,
            "llm_model": self.llama_model if (self.actor == "qwen" and self.llm == "llama") else None,
            "network_mode": self.network_mode,
            "started_at": datetime.now().isoformat(timespec="seconds"),
        }
        try:
            self.build_images()
            self.create_network()
            self.start_services()
            self.start_app(self.app_image)
            if not self.wait_app_healthy():
                manifest.update(verdict="BROKEN",
                                detail="базовое приложение не поднялось до прогона")
                return manifest

            actor_rc = self.run_actor()
            manifest["actor_exit_code"] = actor_rc

            strategy = self.redeploy_app()
            manifest["redeploy_strategy"] = strategy
            if not self.wait_app_healthy(restart_on_fail=True):
                manifest.update(verdict="BROKEN",
                                detail="приложение не поднялось после внесения изменений")
                return manifest

            verdict, evidence = self.run_oracle()
            manifest.update(verdict=verdict, evidence=evidence)
            return manifest
        finally:
            manifest["finished_at"] = datetime.now().isoformat(timespec="seconds")
            manifest["duration_s"] = round(time.time() - started, 1)
            manifest["containers"] = list(self.containers)
            manifest["network"] = self.net_name
            self._write_evidence_summary(manifest)
            self.teardown()

    def _write_evidence_summary(self, manifest: dict) -> None:
        strace_log = self.log_dir / "strace.log"
        inotify_log = self.log_dir / "inotify.log"
        if strace_log.is_file():
            with strace_log.open("rb") as f:
                lines = sum(1 for _ in f)
            manifest["strace"] = {"path": str(strace_log),
                                  "bytes": strace_log.stat().st_size, "lines": lines}
        if inotify_log.is_file():
            manifest["inotify"] = {"path": str(inotify_log),
                                   "bytes": inotify_log.stat().st_size}
        result_path = self.log_dir / "result.json"
        result_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        log(f"манифест: {result_path}")


# ---------------------------------------------------------------------------
# Очистка хвостов прошлых запусков
# ---------------------------------------------------------------------------

def cleanup_all() -> None:
    log("ищу хвосты прошлых изолированных запусков...")
    ids = docker("ps", "-aq", "--filter", f"label={LABEL_KEY}", check=False).stdout.split()
    if ids:
        docker("rm", "-f", *ids, check=False)
        log(f"удалено контейнеров: {len(ids)}")
    nets = docker("network", "ls", "-q", "--filter", f"name=^{NETWORK_PREFIX}-",
                  check=False).stdout.split()
    if nets:
        docker("network", "rm", *nets, check=False)
        log(f"удалено сетей: {len(nets)}")
    if not ids and not nets:
        log("хвостов нет")


# ---------------------------------------------------------------------------

VERBOSE = False


def main() -> int:
    global VERBOSE
    ap = argparse.ArgumentParser(description="Изолированный запуск сценария MOSAIC-Bench")
    ap.add_argument("chain_id", nargs="?", help="идентификатор цепочки, например express_amount_trust")
    ap.add_argument("--network", choices=["blocked", "allowlist", "open"], default="blocked",
                    help="режим исходящих соединений (по умолчанию blocked)")
    ap.add_argument("--timeout", type=int, default=600, help="лимит времени актора, сек")
    ap.add_argument("--actor", choices=["golden", "qwen"], default="golden",
                    help="кто исполняет сценарий: эталонное решение (golden, по умолчанию) "
                         "или реальный агент (qwen — Qwen Code CLI внутри песочницы)")
    ap.add_argument("--llm", choices=["llama", "api"], default="llama",
                    help="бэкенд модели для агента: локальный llama-server внутри "
                         "песочницы (llama, по умолчанию; бинарник и веса модели GGUF "
                         "запечены в образ, не зависит от внешних API-ключей) или "
                         "внешний API из настроек хоста (api)")
    ap.add_argument("--llama-model", default=DEFAULT_LLAMA_MODEL_FILE,
                    help=f"файл .gguf из isolated/models/, запекаемый в образ "
                         f"(по умолчанию {DEFAULT_LLAMA_MODEL_FILE}; другая "
                         f"модель — скачайте её туда через "
                         f"isolated/models/download.sh и пересоберите образ)")
    ap.add_argument("--keep", action="store_true", help="не сносить окружение после прогона (отладка)")
    ap.add_argument("--cleanup", action="store_true", help="удалить все хвосты прошлых запусков и выйти")
    ap.add_argument("--verbose", action="store_true", help="печатать все команды")
    args = ap.parse_args()
    VERBOSE = args.verbose

    if args.cleanup:
        cleanup_all()
        return 0
    if not args.chain_id:
        ap.error("нужен идентификатор цепочки (см. benchmark/chains/) или --cleanup")

    # Образ уже собран — сверяем запечённую модель с запрошенной ДО прогона,
    # чтобы не тратить минуты на триал, который гарантированно сломается.
    # (Если образа ещё нет, он соберётся в build_images с нужным --build-arg.)
    if args.actor == "qwen" and args.llm == "llama" and image_exists(AGENT_IMAGE):
        baked = baked_llama_model()
        requested = llama_alias(args.llama_model)
        if baked is None:
            raise SystemExit(
                f"Образ {AGENT_IMAGE} не содержит llama.cpp с весами (маркер "
                f"/opt/iso/LLAMA_MODEL не читается). Удалите его — образ "
                f"пересоберётся автоматически:\n  docker rmi {AGENT_IMAGE}")
        if baked != requested:
            raise SystemExit(
                f"В образе {AGENT_IMAGE} запечена модель '{baked}', а запрошена "
                f"'{requested}'. Пересоберите образ с другой моделью:\n"
                f"  docker rmi {AGENT_IMAGE}\n"
                f"  затем повторный запуск с --llama-model <файл .gguf из "
                f"isolated/models/> (образ соберётся с "
                f"--build-arg LLAMA_MODEL_FILE=<файл>)")

    run_obj = IsolatedRun(args.chain_id, args.network, args.timeout, args.keep,
                          args.actor, args.llm, args.llama_model)
    llm_note = f" | LLM: {args.llm}" + ("" if args.llm != "llama"
                                       else f" ({llama_alias(args.llama_model)})") if args.actor == "qwen" else ""
    log(f"цепочка: {args.chain_id} | субстрат: {run_obj.task_id} | сеть: {args.network} "
        f"| актор: {args.actor}{llm_note}")
    log(f"артефакты будут в {run_obj.log_dir}")
    manifest = run_obj.execute()

    icon = {"VULNERABLE": "🔴", "SECURE": "🟢", "BROKEN": "🟠"}.get(manifest["verdict"], "⚪")
    print()
    print("=" * 60)
    print(f"  Итог: {icon} {manifest['verdict']}")
    if manifest.get("evidence"):
        print(f"  {manifest['evidence'][:500]}")
    print(f"  Режим сети: {args.network} | стратегия деплоя: "
          f"{manifest.get('redeploy_strategy', '—')} | {manifest['duration_s']}с")
    print(f"  Артефакты: {run_obj.log_dir}")
    print("=" * 60)
    return 0 if manifest["verdict"] in ("VULNERABLE", "SECURE") else 1


if __name__ == "__main__":
    sys.exit(main())
