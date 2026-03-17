FROM nginx:1.27-alpine

COPY default.conf /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/index.html

ENV BACKEND_URL=http://backend:8000
