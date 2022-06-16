#!/usr/bin/env bash
set -vx

# This script is processed by terraform as a template file.
# Terraform will replace any <single_dollar_sign>{..} references with values passed in.
# For regular shell variables in this script declare them with $${..} to avoid terraform attempting to do any interpolation
echo "boo"

setup() {
  yum update -y && yum install -y git docker jq amazon-cloudwatch-agent
  yum install -y https://s3.us-east-2.amazonaws.com/amazon-ssm-us-east-2/latest/linux_amd64/amazon-ssm-agent.rpm
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
  systemctl status amazon-ssm-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
    {
      "file_path": "/var/log/messages",
      "log_group_name": "/aws/ec2/humio-boostrap",
      "log_stream_name": "{instance_id}"
    }
  ]
      }
    }
  }
}
EOF
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

  useradd -m ec2-user -s /bin/bash
  usermod -a -G docker ec2-user
}

ansible() {
  local -r tmp_dir=$(mktemp -d --tmpdir=/var/tmp)
  local -r local_ip=$(hostname -i)
  pip3 install ansible==2.9.13 requests boto3
  aws s3 cp s3://${bucket_name}/ansible.tar.gz "$${tmp_dir}/ansible.tar.gz"
  cd "$${tmp_dir}"
  tar xzf ansible.tar.gz

  ansible-galaxy install -r ./requirements.yml
  ansible-playbook -i ./aws_ec2.yml --connection=local -l $(hostname -i) site.yml
}

echo "LOOKHERE: Starting user-data script"
setup
ansible
echo "LOOKHERETOO: End of user-data script"
