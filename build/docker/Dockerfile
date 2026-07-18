# PowerShell Core on Debian — Linux에서 Windows 워크플로(verify/run/hooks) 검증용
FROM mcr.microsoft.com/powershell:lts-debian-12

LABEL org.opencontainers.image.title="korean-skills-2026-win-test"
LABEL org.opencontainers.image.description="Windows harness smoke test (PowerShell Core)"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo

COPY build/docker/entrypoint.ps1 /entrypoint.ps1

ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/entrypoint.ps1"]
