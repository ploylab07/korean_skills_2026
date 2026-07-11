# PowerShell on Debian — validates Windows workflow scripts on Linux (CI/dev)
FROM mcr.microsoft.com/powershell:lts-debian-12

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo

COPY build/docker/entrypoint.ps1 /entrypoint.ps1

ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/entrypoint.ps1"]
