FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY book-linux-amd64_v1.0.1 /book
RUN chmod +x /book
EXPOSE 8080
ENTRYPOINT ["/book"]
