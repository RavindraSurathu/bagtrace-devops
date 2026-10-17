# Nginx serves the dashboard and proxies /api to the backend.
# The official image renders /etc/nginx/templates/*.template with envsubst at start-up,
# so BACKEND_HOST/BACKEND_PORT can differ between Docker Compose and Kubernetes.
FROM nginx:1.27-alpine
LABEL org.opencontainers.image.title="bagtrace-frontend"
ENV BACKEND_HOST=backend BACKEND_PORT=8080
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY index.html app.js styles.css /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1/nginx-health || exit 1
