# DSpace 9 — Docker Compose Setup

> Self-contained Docker stack for [DSpace 9.x](https://wiki.lyrasis.org/spaces/DSDOC9x) — інституційний репозитарій з повноцінним Angular UI, REST API, Solr та PostgreSQL.

---

## Архітектура

```
Browser / curl
     │
     ▼
┌──────────────────────────────────────────────────┐
│  nginx  :80   (єдина точка входу)                │
│   ├── /server  ──►  DSpace REST API  :8080        │
│   └── /        ──►  Angular SSR      :4000        │
└──────────────────────────────────────────────────┘
          │                      │
          ▼                      ▼
   PostgreSQL 16          Apache Solr 9.7
```

Angular SSR (Node.js) та nginx share one network namespace, тому обидва звертаються до REST API через однаковий `localhost:80` — без `host.docker.internal` і без змін у hosts-файлі.

---

## Стек

| Сервіс | Образ | Призначення |
|---|---|---|
| `nginx` | `nginx:alpine` | Reverse proxy, єдиний порт :80 |
| `dspace` | custom (Eclipse Temurin 17 JRE) | DSpace REST API (Spring Boot) |
| `dspace-ui` | custom (Node.js 20) | Angular SSR frontend |
| `db` | `postgres:16-alpine` | Основна база даних |
| `solr` | custom (Solr 9.7) | Повнотекстовий пошук |

---

## Вимоги

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) ≥ 4.x (Windows / macOS / Linux)
- Docker Compose v2 (вбудований в Docker Desktop)
- **RAM**: мінімум 6 GB виділених для Docker
- **Диск**: ~8 GB (образи + volume)
- Вільний порт **80** (nginx), **8080** (backend debug), **8983** (Solr debug)

---

## Швидкий старт

### 1. Клонувати репозиторій

```bash
git clone https://github.com/<your-org>/dspace-9-docker.git
cd dspace-9-docker
```

### 2. Налаштувати змінні середовища

```bash
cp .env .env.local   # або відредагуйте .env напряму
```

Мінімальні зміни у `.env`:

```dotenv
DSPACE_ADMIN_EMAIL=admin@example.com
DSPACE_ADMIN_PASS=changeme          # змінити перед production!
DSPACE_NAME=My DSpace Repository
```

### 3. Запустити

```bash
docker compose up -d
```

> **Перший запуск** займає ~15–30 хв: Maven завантажує залежності та збирає DSpace,
> Ant виконує `fresh_install`, мігрує схему БД та створює адмін-акаунт.
> Наступні запуски — секунди.

### 4. Відкрити

| URL | Опис |
|---|---|
| http://localhost | Angular UI |
| http://localhost/server | REST API (HAL Browser) |
| http://localhost:8080/server | REST API напряму (debug) |
| http://localhost:8983/solr | Solr Admin UI (debug) |

---

## Структура проєкту

```
.
├── docker-compose.yml          # оркестрація всіх сервісів
├── Dockerfile.backend          # Maven build + Eclipse Temurin 17 JRE runtime
├── Dockerfile.frontend         # Node.js 20 build + Angular SSR runtime
├── Dockerfile.solr             # Solr 9.7 з DSpace core-конфігами
├── nginx.conf                  # reverse proxy: /server → backend, / → frontend
├── .env                        # налаштування (версія, паролі, порти)
├── config/
│   └── local.build.cfg         # DSpace cfg для стадії Maven-збірки
└── scripts/
    ├── backend-entrypoint.sh   # генерує local.cfg, ant install, DB migrate, запуск
    └── init-db.sql             # CREATE EXTENSION pgcrypto
```

---

## Конфігурація

Всі налаштування зосереджені у файлі `.env`:

```dotenv
# Версія DSpace
DSPACE_VERSION=9.0

# Публічні URL (через nginx на порту 80)
DSPACE_SERVER_URL=http://localhost/server
DSPACE_UI_URL=http://localhost

# Назва репозитарію
DSPACE_NAME=My DSpace Repository

# Адміністратор (створюється автоматично при першому старті)
DSPACE_ADMIN_EMAIL=admin@example.com
DSPACE_ADMIN_PASS=changeme

# База даних
DB_NAME=dspace
DB_USER=dspace
DB_PASS=dspace

# Порти
PROXY_PORT=80        # nginx (головний)
BACKEND_PORT=8080    # backend (debug)
SOLR_PORT=8983       # Solr (debug)

# JVM
JAVA_OPTS=-Xmx2g -Xms512m -Dfile.encoding=UTF-8
```

---

## Корисні команди

```bash
# Статус контейнерів
docker compose ps

# Логи конкретного сервісу
docker compose logs -f dspace
docker compose logs -f dspace-ui
docker compose logs -f nginx

# Зупинити без видалення даних
docker compose stop

# Зупинити та видалити контейнери (дані у volumes збережено)
docker compose down

# Повне скидання (видаляє всі дані!)
docker compose down -v

# Перезбірка після зміни коду
docker compose up -d --build dspace
docker compose up -d --build dspace-ui
```

---

## DSpace CLI

```bash
# Зайти в контейнер backend
docker exec -it dspace-backend bash

# DSpace CLI всередині контейнера
/dspace/bin/dspace --help

# Реіндексувати Solr
/dspace/bin/dspace index-discovery -b

# Переміграти базу даних
/dspace/bin/dspace database migrate
```

---

## Як це працює

### Мережа — nginx + dspace-ui shared namespace

`dspace-ui` використовує `network_mode: "service:nginx"` — обидва контейнери ділять
**один мережевий простір** (як поди в Kubernetes). Завдяки цьому:

- SSR Node.js викликає `http://localhost/server` → потрапляє в nginx → backend ✓
- Браузер викликає `http://localhost/server` → той самий nginx на порту 80 → backend ✓
- Жодних спеціальних DNS-хаків не потрібно

> Node.js 18+ прив'язується до `::1` (IPv6 loopback) замість `127.0.0.1`.
> Тому nginx використовує `[::1]:4000` як upstream для Angular SSR.

### Перший запуск — backend entrypoint

```
1. Генерується /dspace/config/local.cfg з env-змінних
2. ant fresh_install  — копіює файли, підключається до БД
3. dspace database migrate  — застосовує Flyway-міграції
4. dspace create-administrator  — створює адмін-акаунт
5. java -jar server-boot.jar  — стартує Spring Boot
```

Маркер `.initialized` у persistent volume гарантує, що кроки 2–4 виконуються лише одного разу.

---

## Production-рекомендації

- [ ] Замінити всі паролі у `.env`
- [ ] Налаштувати HTTPS (Certbot + nginx або зовнішній Load Balancer)
- [ ] Збільшити `JAVA_OPTS` для великих репозитаріїв (`-Xmx4g -Xms1g`)
- [ ] Налаштувати backup для volumes `pgdata` та `dspace_home`
- [ ] Вимкнути відкриті debug-порти `8080` та `8983` у `docker-compose.yml`
- [ ] Налаштувати зовнішній SMTP (`mail.*` у `local.cfg` або через env)

---

## Вирішення проблем

**502 Bad Gateway** після перезапуску nginx  
nginx та dspace-ui треба перезапускати разом (вони діляють network namespace):
```bash
docker compose restart nginx dspace-ui
```

**Перший старт дуже довгий**  
Нормально. Maven завантажує ~500 MB залежностей. Наступні збірки кешовані завдяки BuildKit `.m2` cache mount.

**`/dspace/config/local.cfg: No such file or directory`**  
Volume `dspace_home` містить маркер від невдалої попередньої установки. Повне скидання:
```bash
docker compose down -v && docker compose up -d
```

**Solr healthcheck не проходить**  
Зачекайте 2–3 хв після першого старту — Solr повільно ініціалізує cores.

---

## Ліцензія

DSpace розповсюджується під ліцензією [BSD 3-Clause](https://github.com/DSpace/DSpace/blob/main/LICENSE).  
Docker-конфігурація у цьому репозиторії — MIT.
