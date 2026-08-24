param(
    [string]$DumpPath = ""
)
. (Join-Path $PSScriptRoot "lib.ps1")
foreach ($cmd in @("terraform", "aws", "kubectl")) { Require-Command $cmd }
Ensure-CoreState
Ensure-Kubeconfig

$region = Get-AwsRegion
$s3Bucket = Get-TfOutputRaw "image_bucket_name"
$bootstrapKey = ""
$tempYaml = Join-Path ([IO.Path]::GetTempPath()) ("rds-init-{0}.yaml" -f [guid]::NewGuid())

try {
    Invoke-Kubectl apply -f (Join-Path $Script:K8sDir "namespace-and-serviceaccounts.yaml")
    & kubectl -n app get secret app-db *> $null
    if ($LASTEXITCODE -ne 0) { Fail "Run 02-create-runtime-config.ps1 first." }

    if (-not [string]::IsNullOrWhiteSpace($DumpPath)) {
        $DumpPath = (Resolve-Path $DumpPath).Path
        if (-not (Test-Path $DumpPath -PathType Leaf)) { Fail "Dump file not found: $DumpPath" }
        $bootstrapKey = "_bootstrap/load_user-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).dump"
        Write-Step "Upload dump temporarily to private S3"
        Invoke-Aws s3 cp $DumpPath "s3://$s3Bucket/$bootstrapKey" --region $region --only-show-errors
    }

    & kubectl -n app delete job rds-init --ignore-not-found | Out-Host

    if ($bootstrapKey) {
        $yaml = @'
apiVersion: batch/v1
kind: Job
metadata:
  name: rds-init
  namespace: app
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app: rds-init
    spec:
      serviceAccountName: db-init-sa
      restartPolicy: Never
      volumes:
        - name: work
          emptyDir: {}
      initContainers:
        - name: download-dump
          image: public.ecr.aws/aws-cli/aws-cli:latest
          envFrom:
            - configMapRef:
                name: app-config
          command: ["/bin/sh", "-ec"]
          args:
            - aws s3 cp "s3://${S3_BUCKET}/__BOOTSTRAP_KEY__" /work/load_user.dump --region "${AWS_REGION}"
          volumeMounts:
            - name: work
              mountPath: /work
      containers:
        - name: mysql
          image: public.ecr.aws/docker/library/mysql:8.0
          envFrom:
            - secretRef:
                name: app-db
          command: ["/bin/bash", "-ec"]
          args:
            - |
              until mysqladmin ping -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent; do
                echo "Waiting for RDS..."
                sleep 5
              done

              mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
                -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DBNAME\`;"

              mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DBNAME" <<'SQL'
              CREATE TABLE IF NOT EXISTS user (
                id VARCHAR(255) NOT NULL,
                username VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                PRIMARY KEY (id),
                UNIQUE KEY uk_username (username),
                INDEX idx_user_email (email)
              );

              CREATE TABLE IF NOT EXISTS product (
                id VARCHAR(255) NOT NULL,
                name VARCHAR(255) NOT NULL,
                price FLOAT(8) NOT NULL,
                image_path VARCHAR(500) DEFAULT NULL,
                PRIMARY KEY (id)
              );
              SQL

              mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DBNAME" < /work/load_user.dump
          volumeMounts:
            - name: work
              mountPath: /work
'@
        $yaml = $yaml.Replace('__BOOTSTRAP_KEY__', $bootstrapKey)
    }
    else {
        $yaml = @'
apiVersion: batch/v1
kind: Job
metadata:
  name: rds-init
  namespace: app
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app: rds-init
    spec:
      serviceAccountName: db-init-sa
      restartPolicy: Never
      containers:
        - name: mysql
          image: public.ecr.aws/docker/library/mysql:8.0
          envFrom:
            - secretRef:
                name: app-db
          command: ["/bin/bash", "-ec"]
          args:
            - |
              until mysqladmin ping -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent; do
                echo "Waiting for RDS..."
                sleep 5
              done

              mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
                -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DBNAME\`;"

              mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DBNAME" <<'SQL'
              CREATE TABLE IF NOT EXISTS user (
                id VARCHAR(255) NOT NULL,
                username VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                PRIMARY KEY (id),
                UNIQUE KEY uk_username (username),
                INDEX idx_user_email (email)
              );

              CREATE TABLE IF NOT EXISTS product (
                id VARCHAR(255) NOT NULL,
                name VARCHAR(255) NOT NULL,
                price FLOAT(8) NOT NULL,
                image_path VARCHAR(500) DEFAULT NULL,
                PRIMARY KEY (id)
              );
              SQL
'@
    }

    [IO.File]::WriteAllText($tempYaml, $yaml, [Text.UTF8Encoding]::new($false))
    Write-Step "Run RDS initialization Job"
    Invoke-Kubectl apply -f $tempYaml

    & kubectl -n app wait --for=condition=complete job/rds-init --timeout=15m | Out-Host
    if ($LASTEXITCODE -ne 0) {
        & kubectl -n app describe job rds-init | Out-Host
        & kubectl -n app logs job/rds-init --all-containers=true | Out-Host
        Fail "RDS initialization Job failed."
    }
    Invoke-Kubectl -n app logs job/rds-init -c mysql

    if ($bootstrapKey) {
        Write-Step "Delete temporary dump object"
        Invoke-Aws s3 rm "s3://$s3Bucket/$bootstrapKey" --region $region --only-show-errors
        $bootstrapKey = ""
    }
}
finally {
    Remove-Item $tempYaml -Force -ErrorAction SilentlyContinue
    if ($bootstrapKey) {
        & aws s3 rm "s3://$s3Bucket/$bootstrapKey" --region $region --only-show-errors *> $null
    }
}
