FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY book-linux-amd64_v1.0.1 /app/book
RUN chmod +x /app/book
EXPOSE 8080
ENTRYPOINT ["/app/book"]
