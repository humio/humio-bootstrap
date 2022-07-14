#!/usr/bin/env bash
set -vx
#set -eu

# echo "sleeping 300 here"
# sleep 300 
# install needed packages
setup() {
  if [[ $(uname -a) =~ "Ubuntu" ]]; then
    apt-get update -y && \
    apt-get install -y ec2-instance-connect jq ca-certificates curl unzip \
                      python3 openssh-client iproute2 python3-pip nvme-cli mdadm
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf ./aws
    # curl -O -s https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    # dpkg -i -E ./amazon-cloudwatch-agent.deb
    echo "ec2-user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ec2-user
    apt-get clean && rm -rf /var/lib/apt/lists/*
  else
    yum update -y && \
    yum install -y jq ca-certificates curl python3  python3-pip nvme-cli mdadm
    # this seems to conflict with amzon installing this automatically
    # yum install -y https://s3.us-east-2.amazonaws.com/amazon-ssm-us-east-2/latest/linux_amd64/amazon-ssm-agent.rpm
    # systemctl enable amazon-ssm-agent
    # systemctl start amazon-ssm-agent
    # yum install -y amazon-cloudwatch-agent
  fi
  # Set up permissions for humio directories
  # add check if user exists
  if [ $(getent passwd humio  > /dev/null) ]; then
    echo "skippping user addition"
  else
    useradd humio
    if [ -d "/var/humio" ]; then
      chown humio:humio /var/humio
    fi
  fi

  export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)
}

# setup nvme drive(s) if they exist
nvme_setup() {
  IFS=$'\n'

  declare -r mount_path=/var/humio
  declare -a disks=($(nvme list | grep "NVMe Instance Storage" | awk '{print $1}'))

  mount_disk() {
    local -r device=$1
    local -r path=$2

    if ! [ -d $path ]; then
      mkdir -p $path
    fi
    mount -t ext4 $device $path
  }


  if [ "${#disks[@]}" -eq "1" ]; then

    # only proceed if there is NO filesystem
    if [ ! -f $mount_path ];then
      mkfs -t ext4 $disks \
        && mount_disk $disks $mount_path
        fstab_entry="$disks $mount_path ext4 defaults,nofail  0 2"
        echo $fstab_entry >> /etc/fstab
    fi
  fi

  if [ "${#disks[@]}" -gt "1" ]; then
    # only proceed if there is no raid
    if [ ! -f /dev/md0 ];then
      mdadm --create --verbose /dev/md0 --level=0 --raid-devices=${#disks[@]} ${disks[*]}
      mkfs -F -t ext4 /dev/md0 \
        && mount_disk /dev/md0 $mount_path
      fstab_entry="/dev/md0 $mount_path ext4 defaults,nofail  0 2"
      echo $fstab_entry >> /etc/fstab

    fi
  fi
}

# setup EBS drives for kakfa and zookeeper
# THIS ONLY WORKS ON NITRO BASED AWS INSTANCES, maybe
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html#ec2-nitro-instances
# c5, m5, r5, i3, i3en
ebs_setup() {
  # line seperator
  IFS=$'\n'

  # this sorts the list of
  nvmearr=($(nvme list | grep "Elastic Block Store" | awk '{print $8" "$1" "$2}' | sed 's/vol/vol-/g' | sort))
  for i in "${nvmearr[@]}"
  do
    :
    device="$(echo $i | cut -f2 -d ' ')"
    vol="$(echo $i | cut -f3 -d ' ')"

    # check device for non root devices
    datacheck="$(file -s $device | cut -f 2 -d ' ')"

    # only proceed if there is NO filesystem
    if [ "${datacheck}" == "data" ];then

      # This is another approach that can use tags to determine mount point
      # but requires tags be created before the instance is launch on volumes
      # which isn't great for one off non IAC deplpus
      path="$(aws ec2 describe-volumes --volume-id=${vol} | jq -r '.Volumes[]|.Tags[]?|select(.Key == "humio-mount-point")|.Value')"

      if [ ${#path} -gt 0 ];then
        mkfs -t ext4 $device

        if ! [ -d $path ]; then
            mkdir -p $path
        fi
        mount -t ext4 $device $path
        fstab_entry="$device $path ext4 defaults,nofail  0 2"
        echo $fstab_entry >> /etc/fstab
      fi
    fi

  done
}

ansible() {
  # install ansible
  pip3 install ansible==2.9.13 jinja2==3.0.3 requests boto3


  # create facts for ansible usage
  mkdir -p /etc/ansible/facts.d/
  mkdir -p /etc/ansible/humio_config/
  curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone  >/etc/ansible/facts.d/zone.fact
  curl -s http://169.254.169.254/latest/meta-data/hostname  >/etc/ansible/facts.d/hostname.fact
  curl -s http://169.254.169.254/latest/meta-data/hostname | tr -dc '0-9' | sed -e 's/^0*//g' > /etc/ansible/facts.d/cluster_index.fact
  aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) | jq -r '.Reservations[]|.Instances[]|[(.Tags[]?|select(.Key=="humio-cluster-index")|.Value)]' |  jq .[] | sed 's/"//g' > /etc/ansible/facts.d/cluster_index.fact
  cluster_id=$(aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) | jq -r '.Reservations[]|.Instances[]|[(.Tags[]?|select(.Key=="humio-cluster-id")|.Value)]' |  jq .[] | sed 's/"//g' | sed 's/-/_/g')
  humio_bootstrap_config=$(aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) | jq -r '.Reservations[]|.Instances[]|[(.Tags[]?|select(.Key=="humio-bootstrap-config")|.Value)]' |  jq .[] | sed 's/"//g')


  # The below should be updated
  # Update this to the URL of the server
  # how do we put this somewhere else?
  echo '"https://test.humio.net"' > /etc/ansible/facts.d/public_url.fact

  # download ansible config and other info
  # tar xzvf /etc/ansible/ansible.tar.gz -C /etc/ansible

  # get IP fo local execution limit
  local -r local_hostname=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
  local -r tmp_dir=$(mktemp -d --tmpdir=/var/tmp)

  # local -r local_ip=$(hostname -i)
  # pip3 install ansible==2.9.13 requests boto3
  aws s3 cp s3://$humio_bootstrap_config/ansible.zip "${tmp_dir}"
  cd "${tmp_dir}"
  unzip ansible.zip
  mkdir group_vars
  mv group_vars.yml group_vars/all.yml

  /usr/local/bin/ansible-galaxy install -r ./requirements.yml
  # ansible-playbook -i ./aws_ec2.yml --connection=local -l $(hostname -i) site.yml

  # aws s3 cp s3://$humio_bootstrap_config/ansible.cfg /etc/ansible/
  # aws s3 cp s3://$humio_bootstrap_config/aws_ec2.yml /etc/ansible/
  # aws s3 cp s3://$humio_bootstrap_config/requirements.yml /etc/ansible/
  # aws s3 cp s3://$humio_bootstrap_config/group_vars.yml /etc/ansible/group_vars/all.yml
  # aws s3 cp s3://$humio_bootstrap_config/humio-bootstrap.yml /etc/ansible/humio-bootstrap.yml
  # aws s3 cp s3://$humio_bootstrap_config/humio.conf /etc/ansible/humio_config/humio.conf


  # install ansible requirements
  # /usr/local/bin/ansible-galaxy install -r /etc/ansible/requirements.yml

  /usr/local/bin/ansible-playbook -i ./aws_ec2.yml --connection=local -l $local_hostname ./humio-bootstrap.yml -e humio_cluster_id=$cluster_id

}
setup
nvme_setup
ebs_setup
ansible