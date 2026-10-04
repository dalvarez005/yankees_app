# App web (PWA) del club: nginx con la app de Flutter ya compilada adentro.
# La imagen no ejecuta nada al construirse (solo COPY), así que se construye
# para el servidor ARM desde la PC sin emulación. Ver deploy/web/deploy.sh.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html/ /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
