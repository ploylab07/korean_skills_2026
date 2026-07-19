resource "aws_kms_key" "s3" {
  description             = "S3 CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "s3" {
  name          = "alias/wskorea26-s3-key"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "dynamodb" {
  description             = "DynamoDB CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/wskorea26-dynamodb-key"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_kms_key" "eks" {
  description             = "EKS secrets CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/wskorea26-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_key" "ecr" {
  description             = "ECR CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/wskorea26-ecr-key"
  target_key_id = aws_kms_key.ecr.key_id
}
