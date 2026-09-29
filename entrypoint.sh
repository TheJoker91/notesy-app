cat > entrypoint.sh << 'EOF'
#!/bin/sh
set -e
python manage.py migrate --noinput
exec "$@"
EOF