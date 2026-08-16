# Windows Terraform provider mirror (offline)

Bundled `windows_amd64` providers for contest PCs that cannot download from
`releases.hashicorp.com` reliably.

## Layout

```
build/tf-mirror/registry.terraform.io/hashicorp/<name>/...
```

AWS provider zips are split into `.part.00`, `.part.01`, ... because GitHub
rejects files over 100MB. `build/ensure-tf-mirror.ps1` concatenates them on
first run.

## Used by

- `build/terraform.ps1` (via `.\terraform.cmd`)
- `build/start.ps1` (via `.\start.cmd`)

Sets `TF_CLI_CONFIG_FILE` to a generated `build/terraform.rc` that forces
`filesystem_mirror` and disables direct registry downloads.
