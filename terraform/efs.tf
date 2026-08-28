resource "aws_efs_file_system" "hermes" {
  creation_token = "${local.name}-hermes"
  encrypted      = true
  kms_key_id     = aws_kms_key.this.arn

  throughput_mode = "elastic"

  tags = {
    Name = "${local.name}-hermes"
  }
}

resource "aws_efs_backup_policy" "hermes" {
  file_system_id = aws_efs_file_system.hermes.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_mount_target" "hermes" {
  count = 2

  file_system_id  = aws_efs_file_system.hermes.id
  subnet_id       = aws_subnet.application[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "hermes" {
  file_system_id = aws_efs_file_system.hermes.id

  posix_user {
    uid = 10000
    gid = 10000
  }

  root_directory {
    path = "/hermes"
    creation_info {
      owner_uid   = 10000
      owner_gid   = 10000
      permissions = "0750"
    }
  }
}
