# Provided binary is a statically linked Go executable (CGO disabled) —
# distroless "static" needs nothing else besides the CA bundle it ships with.
FROM gcr.io/distroless/static-debian12:nonroot

COPY book /book

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/book"]
