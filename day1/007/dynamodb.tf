resource "aws_dynamodb_table" "concert" {
  name         = "unicorn-concert-db"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"

  attribute {
    name = "booking_id"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "client-id-created-at-index"
    hash_key        = "client_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.app.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = merge(local.common_tags, { Name = "unicorn-concert-db" })
}

resource "null_resource" "dynamodb_unprotect_on_destroy" {
  triggers = {
    table = aws_dynamodb_table.concert.name
  }

  depends_on = [aws_dynamodb_table.concert]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      NAME="${self.triggers.table}"
      aws dynamodb update-table --table-name "$NAME" --no-deletion-protection-enabled >/dev/null || true
      sleep 5
    EOT
  }
}
