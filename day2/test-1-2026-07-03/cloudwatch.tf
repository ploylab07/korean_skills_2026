resource "aws_cloudwatch_log_group" "pod" {
  name              = "/wsc/pod/log"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.main.arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.prefix}-eks-cluster/cluster"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.main.arn
  tags              = local.common_tags
}
