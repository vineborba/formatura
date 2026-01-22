FROM alpine:latest
WORKDIR /app
COPY zig-cache/zig-out/bin/formatura /app
COPY zig-cache/public/ /app/public/
ENTRYPOINT ["formatura"]
