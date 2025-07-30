# WeatherAgent

WeatherAgent — это микросервис на Julia для:

* 📊 Периодического сбора метеоданных (ClickHouse)
* 👥 Управления пользователями (PostgreSQL)
* 🌐 HTTP API для создания, изменения, удаления и получения пользователей

---

## 📁 Структура репозитория

```
WeatherAgent/
├── docker-compose.yml      # Описание сервисов: postgres, clickhouse, weather-api
├── Dockerfile              # Инструкции по сборке Docker-образа приложения
├── Project.toml            # Зависимости Julia-проекта
├── Manifest.toml           # Фиксация версий зависимостей
└── src/
    ├── WeatherAPI.jl       # Точка входа: подключает модули и запускает сервер
    ├── UserInterface.jl    # Инициализация PostgreSQL и операции с пользователями
    ├── DataCollector.jl    # Инициализация ClickHouse и сбор/запись погоды
    └── Handlers.jl         # Маршрутизация HTTP-запросов к функциям UserInterface
```

---

## 📦 Сборка и запуск

1. Склонируйте репозиторий и перейдите в папку проекта:

   ```bash
   git clone https://github.com/ilyaytrewq/WeatherAPI.git
   cd WeatherAgent
   ```
2. Поднимите все сервисы командой:

   ```bash
   docker compose up --build
   ```

Сервисы:

* **postgres**: хранит таблицу `users`
* **clickhouse**: хранит таблицы `weather_metrics` и `cities`
* **weather-api**: само приложение на Julia

---

## 🎛 Переменные окружения

Сервис `weather-api` читает переменные из `docker-compose.yml`:

| Переменная            | Описание                | Пример          |
| --------------------- | ----------------------- | --------------- |
| `POSTGRES_HOST`       | Хост PostgreSQL         | `postgres`      |
| `POSTGRES_PORT`       | Порт PostgreSQL         | `5432`          |
| `POSTGRES_USER`       | Пользователь PostgreSQL | `test_user`     |
| `POSTGRES_PASSWORD`   | Пароль PostgreSQL       | `test_password` |
| `POSTGRES_NAME`       | Имя БД PostgreSQL       | `test_user_db`  |
| `CLICKHOUSE_HOST`     | Хост ClickHouse         | `clickhouse`    |
| `CLICKHOUSE_PORT`     | HTTP-порт ClickHouse    | `8123`          |
| `CLICKHOUSE_USER`     | Пользователь ClickHouse | `default`       |
| `CLICKHOUSE_PASSWORD` | Пароль ClickHouse       | (пусто)         |
| `CLICKHOUSE_DB`       | Имя БД ClickHouse       | `default`       |

---

## 🚀 HTTP API

Сервис слушает порт **8080**. Все маршруты начинаются с `/v1.0.0/`.

### 1. Создать пользователя

```http
POST /v1.0.0/create_user
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "secret",
  "telegram": "@nick",
  "ways_to_send": "T"
}
```

* Ответ: `201 Created`
* Ошибка: `409 Conflict`, если такой email уже есть

### 2. Изменить данные пользователя

```http
POST /v1.0.0/change_user_data
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "newpass",
  "telegram": "@newnick",
  "ways_to_send": "E"
}
```

* Ответ: `200 OK`
* Ошибка: `400 Bad Request`, если не указано `email`

### 3. Удалить пользователя

```http
POST /v1.0.0/delete_user
Content-Type: application/json

{
  "email": "user@example.com"
}
```

* Ответ: `200 OK`
* Ошибка: `400 Bad Request`, если не указано `email`

### 4. Получить данные пользователя

```http
GET /v1.0.0/get_user_data/email=user@example.com
```

* Ответ: `200 OK`, JSON с полями `email`, `telegram`, `ways_to_send`
* Ошибка: `404 Not Found`, если пользователь не найден

---

## 🔄 Периодическая запись погоды

Модуль `DataCollector` запускает асинхронную задачу:

1. Считывает список городов из таблицы `cities` в ClickHouse.
2. Запрашивает координаты и данные погоды у OpenWeatherMap.
3. Записывает метрики в таблицу `weather_metrics`.

---

## 🛠 Отладка

* Логи сервиса:

  ```bash
  docker compose logs weather-api
  ```
* Подключение к PostgreSQL:

  ```bash
  docker compose exec postgres psql -U test_user -d test_user_db
  ```
* Подключение к ClickHouse:

  ```bash
  docker compose exec clickhouse clickhouse-client --user logs
  ```
