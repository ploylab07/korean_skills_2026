# Alpine provides /bin/sh so preStop graceful sleep matches mark.sh expected output.
FROM alpine:3.20

COPY book /book
RUN chmod +x /book

EXPOSE 8080
ENTRYPOINT ["/book"]
