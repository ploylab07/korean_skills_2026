FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY book /book
RUN chmod +x /book
ENV AWS_REGION=ap-northeast-2
ENV TABLE_NAME=wskorea26-data-table
EXPOSE 8080
USER nobody
CMD ["/book"]
