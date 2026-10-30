# version 4.0.1
FROM alpine:3.22
RUN apk add --no-cache nginx nginx-mod-stream && mkdir -p /run/nginx
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 443/tcp
CMD ["nginx", "-g", "daemon off;"]
