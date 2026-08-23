variable "participant_id" {
  description = "비번호 (S3 버킷명 접미사). terraform.tfvars 또는 .env 의 PARTICIPANT_ID. 전역 유일 — 001 은 BucketAlreadyExists."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z-]{1,20}$", var.participant_id)) && var.participant_id != "001"
    error_message = "PARTICIPANT_ID(.env) 또는 day2/002/terraform.tfvars 에 본인 비번호를 넣으세요. \"001\" 은 S3 전역 충돌로 사용 불가."
  }
}
