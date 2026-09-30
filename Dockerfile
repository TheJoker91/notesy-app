# ---- Stage 1: build the TypeScript bundle ----
FROM node:20-alpine AS frontend
WORKDIR /build
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY apps/notes/static_src ./apps/notes/static_src
RUN npm run typecheck && npm run build     # outputs static/js/*.js

# ---- Stage 2: Python runtime (no Node) ----
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app

RUN useradd --create-home --uid 1000 app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=app:app . .
COPY --from=frontend --chown=app:app /build/static/js ./static/js

# Collect static files for WhiteNoise; make the entrypoint executable.
# The secret key and database URL are throwaway values for this one command only:
# collectstatic never touches the database, and neither value is kept in the image's env.
RUN DJANGO_SECRET_KEY=build-only DATABASE_URL=sqlite:////tmp/build.sqlite3 python manage.py collectstatic --noinput \
    && chmod +x entrypoint.sh \
    && chown -R app:app /app

USER app
EXPOSE 8000

# Entrypoint runs migrations, then hands off to CMD
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "notesy.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--worker-class", "gthread", "--threads", "4", "--access-logfile", "-"]