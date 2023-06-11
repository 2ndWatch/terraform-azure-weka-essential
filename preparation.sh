#!/bin/bash
set -ex

# set apt private repo
if [[ "${apt_repo_url}" != "" ]]; then
  mv /etc/apt/sources.list /etc/apt/sources.list.bak
  echo "deb ${apt_repo_url} focal main restricted universe" > /etc/apt/sources.list
  echo "deb ${apt_repo_url} focal-updates main restricted" >> /etc/apt/sources.list
fi

INSTALLATION_PATH="/tmp/weka"
mkdir -p $INSTALLATION_PATH

for(( i=0; i<${nics_num}; i++ )); do
    cat <<-EOF | sed -i "/        eth$i/r /dev/stdin" /etc/netplan/50-cloud-init.yaml
            mtu: 3900
EOF
done

# config network with multi nics
for(( i=0; i<${nics_num}; i++)); do
  echo "20$i eth$i-rt" >> /etc/iproute2/rt_tables
done

echo "network:"> /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
echo "  config: disabled" >> /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
gateway=$(ip r | grep default | awk '{print $3}')
for(( i=0; i<${nics_num}; i++ )); do
  eth=$(ifconfig | grep eth$i -C2 | grep 'inet ' | awk '{print $2}')
  cat <<-EOF | sed -i "/            set-name: eth$i/r /dev/stdin" /etc/netplan/50-cloud-init.yaml
            routes:
             - to: ${subnet_range}
               via: $gateway
               metric: 200
               table: 20$i
             - to: 0.0.0.0/0
               via: $gateway
               table: 20$i
            routing-policy:
             - from: $eth/32
               table: 20$i
             - to: $eth/32
               table: 20$i
EOF
done

netplan apply

# remove installation path before installing weka
rm -rf $INSTALLATION_PATH

# getNetStrForDpdk bash function definitiion
function getNetStrForDpdk() {
  i=$1
  j=$2
  gateways=$3
  subnets=$4
  net_option_name=$5

  if [ "$#" -lt 5 ]; then
      echo "'net_option_name' argument is not provided. Using default value: --net"
      net_option_name="--net "
  fi

  if [ -n "$gateways" ]; then #azure and gcp
    gateways=($gateways)
  fi

  if [ -n "$subnets" ]; then #azure only
    subnets=($subnets)
  fi

  net=" "
  for ((i; i<$j; i++)); do
    if [ -n "$subnets" ]; then
      subnet=$${subnets[$i]}
      subnet_inet=$(curl -s -H Metadata:true –noproxy “*” http://169.254.169.254/metadata/instance/network\?api-version\=2021-02-01 | jq --arg subnet "$subnet" '.interface[] | select(.ipv4.subnet[0].address==$subnet)' | jq -r .ipv4.ipAddress[0].privateIpAddress)
      eth=$(ifconfig | grep -B 1 "$subnet_inet" |  head -n 1 | cut -d ':' -f1)
    else
      eth=eth$i
      subnet_inet=$(ifconfig $eth | grep 'inet ' | awk '{print $2}')
    fi
    if [ -z "$subnet_inet" ];then
      net=""
      break
    fi
    enp=$(ls -l /sys/class/net/$eth/ | grep lower | awk -F"_" '{print $2}' | awk '{print $1}') #for azure
    if [ -z $enp ];then
      enp=$(ethtool -i $eth | grep bus-info | awk '{print $2}') #pci for gcp
    fi
    bits=$(ip -o -f inet addr show $eth | awk '{print $4}')
    IFS='/' read -ra netmask <<< "$bits"

    if [ -n "$gateways" ]; then
      gateway=$${gateways[$i]}
      net="$net $net_option_name$enp/$subnet_inet/$${netmask[1]}/$gateway"
    else
      net="$net $net_option_name$eth" #aws
    fi
	done
}

# https://gist.github.com/fungusakafungus/1026804
function retry {
  local retry_max=$1
  local retry_sleep=$2
  shift 2
  local count=$retry_max
  while [ $count -gt 0 ]; do
      "$@" && break
      count=$(($count - 1))
      echo "Retrying $* in $retry_sleep seconds..."
      sleep $retry_sleep
  done
  [ $count -eq 0 ] && {
      echo "Retry failed [$retry_max]: $*"
      return 1
  }
  return 0
}
