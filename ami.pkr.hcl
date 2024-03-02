packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "ami_description" {
  type    = string
  default = "Base AMI for Gitpod Next EC2 runners"
}

variable "ami_name" {
  type = string
}

variable "ami_region" {
  type    = string
  default = "us-west-2"
}

variable "arch" {
  type    = string
  default = "x86_64"
}

variable "creator" {
  type    = string
  default = "Gitpod"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  tags = {
    Name                  = "${var.ami_name}"
    buildRegion           = "{{ .BuildRegion }}"
    buildTimestamp        = "${local.timestamp}"
    osName                = "Ubuntu"
    osVersion             = "23.10"
    sourceAMIId           = "{{ .SourceAMI }}"
    sourceAMIName         = "{{ .SourceAMIName }}"
    sourceAMICreationDate = "{{ .SourceAMICreationDate }}"
  }
}

source "amazon-ebs" "linux" {
  region        = var.aws_region
  ami_name      = var.ami_name
  instance_type = "m5.large"

  boot_mode = "legacy-bios"
  ami_virtualization_type = "hvm"
  associate_public_ip_address = true
  ebs_optimized = true
  ena_support = true

  source_ami_filter {
    filters = {
      name                = "*/ubuntu-jammy-23.10-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  tags          = "${local.tags}"
  snapshot_tags = "${local.tags}"
  run_tags      = "${local.tags}"

  ssh_username = "ubuntu"
  temporary_key_pair_type = "ed25519"

  shutdown_behavior = "terminate"
}

build {
  name    = "ec2runner-ami"
  sources = ["source.amazon-ebs.linux"]

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/scripts"
    ]
  }

  provisioner "file" {
    destination = "/tmp/scripts/"
    source      = "${path.root}/scripts/"
  }

  provisioner "shell" {
    inline = [
      "sudo bash -c 'chmod +x /tmp/scripts/*.sh'",
      "sudo -E bash -c /tmp/scripts/bootstrap.sh",
      "sleep 10",
      "sudo reboot --force"
    ]

    expect_disconnect = true
  }

  # After rebooting the node, we are confident the boot
  # record and initial configuration are ok
  provisioner "shell" {
    inline = [
      "echo done"
    ]
  }
}
