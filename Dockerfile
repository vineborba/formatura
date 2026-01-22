FROM scratch
WORKDIR /app
COPY formatura /app/formatura
COPY ./public /app/public/
ENTRYPOINT ["./formatura"]
