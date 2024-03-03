#!/bin/bash

BUILD_TIMESTAMP="$(date -u +'%Y%m%d-%H%M')"
GENERATED_AMI_NAME="gitpod/images/gitpod-next/ec2-runner-ami-${BUILD_TIMESTAMP}"

packer init ami.pkr.hcl

packer build \
	-timestamp-ui \
	-color=false \
	-var ami_name="${GENERATED_AMI_NAME}" \
	ami.pkr.hcl
