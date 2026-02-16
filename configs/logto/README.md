Logto configuration

This folder is a placeholder for Logto configuration files (database migrations, presets, env files).

You should provide a `LOGTO_DATABASE_URL` environment variable pointing to a Postgres/MySQL database for Logto to use. Example `.env` entries:

```
LOGTO_DATABASE_URL=postgres://user:pass@postgres:5432/logto_db
LOGTO_APP_ID=logto
LOGTO_APP_SECRET=change-me
LOGTO_HOST=auth.local
LOGTO_PORT=3000
```

Place any Logto config templates in this folder and mount them into the container at `/etc/logto`.
