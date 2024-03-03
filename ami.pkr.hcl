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
  source_ami_filter {
    filters = {
      name                = "*/ubuntu-mantic-23.10-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  region        = var.ami_region
  ami_name      = var.ami_name
  instance_type = "m5.xlarge"

  ami_virtualization_type = "hvm"
  associate_public_ip_address = true
  ebs_optimized = true
  ena_support = true

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 20
    volume_type = "gp3"

    iops = "3000"
    throughput = "250"

    delete_on_termination = true
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

  provisioner "file" {
    destination = "/tmp/devcontainer-seed-images.txt"
    source      = "${path.root}/devcontainer-seed-images.txt"
  }

  provisioner "shell" {
    inline = [
      "sudo bash -c 'chmod +x /tmp/scripts/*.sh'",
      "sudo -E bash -c /tmp/scripts/setup.sh",
      "sudo -E bash -c /tmp/scripts/seed-images.sh",
      "sudo -E bash -c /tmp/scripts/cleanup.sh",
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
