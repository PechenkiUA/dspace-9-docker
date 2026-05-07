Структура проєкту

  dspace-9/
  ├── docker-compose.yml          — оркестрація 4 сервісів
  ├── Dockerfile.backend          — збірка + runtime DSpace REST API
  ├── Dockerfile.frontend         — збірка + runtime Angular UI
  ├── Dockerfile.solr             — Solr 9.7 з DSpace core-конфігами
  ├── .env                        — всі налаштування в одному місці
  ├── config/
  │   └── local.build.cfg         — мінімальний cfg для стадії збірки
  └── scripts/
      ├── backend-entrypoint.sh   — генерує local.cfg з env, мігрує БД, запускає сервер
      └── init-db.sql             — створює розширення pgcrypto

  Архітектура сервісів

  ┌───────────┬─────────────────────────────────────────────┬──────┐
  │  Сервіс   │               Образ / Збірка                │ Порт │
  ├───────────┼─────────────────────────────────────────────┼──────┤
  │ db        │ postgres:16-alpine                          │ —    │
  ├───────────┼─────────────────────────────────────────────┼──────┤
  │ solr      │ Dockerfile.solr (solr:9.7)                  │ 8983 │
  ├───────────┼─────────────────────────────────────────────┼──────┤
  │ dspace    │ Dockerfile.backend (eclipse-temurin:17-jre) │ 8080 │
  ├───────────┼─────────────────────────────────────────────┼──────┤
  │ dspace-ui │ Dockerfile.frontend (node:20-alpine)        │ 4000 │
  └───────────┴─────────────────────────────────────────────┴──────┘

  Запуск

  # 1. Скопіюйте/відредагуйте .env під себе (пошта адміна, паролі тощо)

  # 2. Збірка + запуск (перша збірка ~15-30 хв через Maven)
  docker compose up --build
  ├───────────┼─────────────────────────────────────────────┼──────┤
  │ dspace-ui │ Dockerfile.frontend (node:20-alpine)        │ 4000 │
  └───────────┴─────────────────────────────────────────────┴──────┘

  Запуск

  # 1. Скопіюйте/відредагуйте .env під себе (пошта адміна, паролі тощо)

  # 2. Збірка + запуск (перша збірка ~15-30 хв через Maven)
  docker compose up --build

  # 3. Після запуску відкрийте:
  #    Frontend:  http://localhost:4000
  #    REST API:  http://localhost:8080/server
  #    Solr:      http://localhost:8983/solr

  Важливі примітки

  1. Перша збірка — дуже довга (Maven завантажує залежності). Наступні — швидкі завдяки BuildKit кешу .m2.
  2. Адмін — створюється автоматично при першому старті з DSPACE_ADMIN_EMAIL та DSPACE_ADMIN_PASS з .env.
  3. Frontend CMD — якщо dist/server/main.js не знайдено для вашої версії, перевірте шлях у Dockerfile.frontend (може бути dist/browser/main.js або dist/dspace-angular/server/main.js).
  4. Зворотній проксі — для продакшну рекомендується Nginx перед обома сервісами, щоб UI і API були на одному домені.