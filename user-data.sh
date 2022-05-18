#/usr/bin/env bash


#!/bin/bash


if [[ $(uname -a) =~ "Ubuntu" ]]; then
  apt-get update -y && apt-get install -y git git-lfs ec2-instance-connect unzip make jq ca-certificates curl gnupg lsb-release libnl-genl-3-200
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  ./aws/install
  curl -O -s https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  dpkg -i -E ./amazon-cloudwatch-agent.deb
  echo "ec2-user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ec2-user
else
  yum update -y && yum install -y git docker jq
  yum install -y https://s3.us-east-2.amazonaws.com/amazon-ssm-us-east-2/latest/linux_amd64/amazon-ssm-agent.rpm
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent

  yum install -y amazon-cloudwatch-agent
fi
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
	    "log_group_name": "/aws/ec2/cx-team-ec2",
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


# install and configure tenable
TENABLE_TOKEN=$(aws secretsmanager get-secret-value --secret-id tenable-agent --query SecretString --output text --version-stage AWSCURRENT --region us-east-2 | jq -r '."key"')
aws s3 cp s3://sandbox-us-west-2-internal-tenable-artifacts/NessusAgent-8.2.4-ubuntu1110_amd64.deb /opt/tenable-agent
if [[ $(uname -a) =~ "Ubuntu" ]]; then
  mv /opt/tenable-agent{,.deb}
  dpkg -i /opt/tenable-agent.deb
else
  mv /opt/tenable-agent{,.rpm}
  yum install -y /opt/tenable-agent.rpm
fi

/opt/nessus_agent/sbin/nessuscli agent link --key=${TENABLE_TOKEN} --groups="humio_all" --cloud && \
  /opt/nessus_agent/sbin/nessuscli fix --set update_hostname=\"yes\" && \
  /sbin/service nessusagent start

# install and configure falcon-agent
FALCON_CID=$(aws secretsmanager get-secret-value --secret-id falcon-sensor --query SecretString --output text --version-stage AWSCURRENT --region us-east-2 | jq -r '."cid"')
aws s3 cp s3://sandbox-us-west-2-internal-tenable-artifacts/falcon-sensor_6.33.0-13003_amd64.deb /opt/falcon-agent
if [[ $(uname -a) =~ "Ubuntu" ]]; then
  mv /opt/falcon-agent{,.deb}
  dpkg -i /opt/falcon-agent.deb
else
  mv /opt/falcon-agent{,.rpm}
  yum install -y /opt/falcon-agent.rpm
fi

/opt/CrowdStrike/falconctl -s --cid=${FALCON_CID} && \
  systemctl start falcon-sensor

# install needed packages and updates
apt-get update
apt-get upgrade -y
apt-get install -yq build-essential python jq python python3 \
	openssh-client iproute2 python3-pip nvme-cli mdadm

# setup nvme drive(s) 
set -eu

declare -r mount_path=/var/humio
declare -r disks=($(find /dev/disk/by-id -iname 'nvme-Amazon_EC2_NVMe_Instance_Storage_*'))

mount_disk() {
  local -r device=$1
  local -r path=$2

  if ! [ -d $path ]; then
    mkdir -p $path
  fi
  mount -t ext4 $device $path
}

if [ "${#disks[@]}" -eq "1" ]; then
  mkfs -t ext4 $disks \
    && mount_disk $disks $mount_path
    fstab_entry="$disks $mount_path ext4 defaults,nofail  0 2"
    echo $fstab_entry >> /etc/fstab
fi

if [ "${#disks[@]}" -gt "1" ]; then
  mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${#disks[@]} $${disks[@]}
  if [ "$(blkid /dev/md0)" == "" ]; then
    mkfs -t ext4 /dev/md0 \
      && mount_disk /dev/md0 $mount_path
    fstab_entry="/dev/md0 $mount_path ext4 defaults,nofail  0 2"
    echo $fstab_entry >> /etc/fstab

  fi
fi

# Set up permissions for humio directories
useradd humio
if [ -d "/var/humio" ]; then
  chown humio:humio /var/humio
fi

# setup EBS drives for kakfa and zookeeper
# THIS ONLY WORKS ON NITRO BASED AWS INSTANCES
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html#ec2-nitro-instances
# c5, m5, r5, i3, i3en

# line seperator
IFS=$'\n'

# this sorts the list of
nvmearr=($(nvme list | grep "Elastic Block Store" | awk '{print $8" "$1" "$2}' | sed 's/vol/vol-/g' | sort))
for i in "${#nvmearr[@]}"
do
   :
  device="$(echo ${nvmearr[$i]} | cut -f2 -d ' ')"
  vol="$(echo ${nvmearr[$i]} | cut -f3 -d ' ')"

  # check device for non root devices
  datacheck="$(file -s $device | cut -f 2 -d ' ')"
  
  # only proceed if there is NO filesystem
  if [ "${datacheck}" == "data" ];then
    
    # this assumes the smallest drive without data is for zookeeper
    # it also assumes NO OTHER EBS mounts
    if [ $i -eq 0 ]; then
      path="/var/zookeeper"
    elif; then
      path="/var/kafka"
    fi


    # This is another approach that can use tags to determine mount point
    # but requires tags be created before the instance is launch on volumes
    # which isn't great for one off non IAC deplpus
    # path="$(aws ec2 describe-volumes --volume-id=${vol} | jq -r '.Volumes[]|.Tags[]?|select(.Key == "mount_point")|.Value')"

    # checks if there was a volumed mount_point tag and proceeds if so
    if [ ${#path} -gt 0 ];then
      mkfs -t ext4 $device
    
      if ! [ -d $path ]; then
          mkdir -p $path
      fi
      mount -t ext4 $device $path
      fstab_entry="$device $mount_path ext4 defaults,nofail  0 2"
      echo $fstab_entry >> /etc/fstab
    fi
  fi
done


apt-get clean && rm -rf /var/lib/apt/lists/*

# install ansible
pip3 install ansible==2.9.13 requests boto3

# get IP fo local execution limit
declare -r local_ip=$(/usr/bin/python3 -c 'import requests; print(requests.get("http://169.254.169.254/latest/meta-data/local-ipv4", timeout=5).content.decode("utf-8"))')

# create facts for ansible usage
mkdir -p /etc/ansible/facts.d/
mkdir -p /etc/ansible/humio_config/
curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone  >/etc/ansible/facts.d/zone.fact
curl -s http://169.254.169.254/latest/meta-data/hostname  >/etc/ansible/facts.d/hostname.fact
curl -s http://169.254.169.254/latest/meta-data/hostname | tr -dc '0-9' | sed -e 's/^0*//g' > /etc/ansible/facts.d/cluster_index.fact
aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) | jq -r '.Reservations[]|.Instances[]|[(.Tags[]?|select(.Key=="Name")|.Value)]' | jq .[] | sed 's/"//g' | tr -dc '0-9' | sed -e 's/^0*//g' > /etc/ansible/facts.d/cluster_index.fact


# The below should be updated
# Update this to the URL of the server
echo '"https://grant-bootstrap.cx.humio.net"' > /etc/ansible/facts.d/public_url.fact

# download ansible config and other info
aws s3 cp s3://humio-cx-grant-ansible/ansible.cfg /etc/ansible/
aws s3 cp s3://humio-cx-grant-ansible/aws_ec2.yml /etc/ansible/
aws s3 cp s3://humio-cx-grant-ansible/requirements.yml /etc/ansible/
aws s3 cp s3://humio-cx-grant-ansible/group_vars.yml /etc/ansible/group_vars/all.yml
aws s3 cp s3://humio-cx-grant-ansible/site.yml /etc/ansible/site.yml


# install ansible requirements
ansible-galaxy install -r /etc/ansible/requirements.yml

ansible-playbook -i /etc/ansible/aws_ec2.yml --connection=local -l $local_ip /etc/ansible/site.yml 
