FROM nginxinc/nginx-unprivileged:alpine
USER root
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx index.html /usr/share/nginx/html/index.html
COPY --chown=nginx:nginx entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh
USER nginx
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
