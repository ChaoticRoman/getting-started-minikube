FROM nginx:1.27-alpine

ARG COMMIT_SHA=dev
COPY default.conf /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/index.html
RUN echo "$COMMIT_SHA" > /usr/share/nginx/html/version.txt

ENV BACKEND_URL=http://backend:8000
