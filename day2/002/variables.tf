variable "participant_id" {
  description = "비번호 (S3 버킷명 접미사). 전역 유일 — 001/999 등은 이미 점유되어 BucketAlreadyExists 날 수 있음."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z-]{1,20}$", var.participant_id)) && var.participant_id != "001"
    error_message = "day2/002/terraform.tfvars 에 본인 비번호를 넣으세요. participant_id = \"001\" 은 S3 전역 충돌로 사용 불가."
  }
}
