#
# Helper script for 'gen3 workon' - see ../README.md and ../gen3setup.sh
#

if [[ ! -f "$GEN3_HOME/gen3/lib/common.sh" ]]; then
  echo "ERROR: no $GEN3_HOME/gen3/lib/common.sh"
  exit 1
fi

help() {
  cat - <<EOM
  Use: gen3 workon aws-profile vpc-name
     Prepares a local workspace to run terraform and other devops tools.
EOM
  return 0
}

source "$GEN3_HOME/gen3/lib/common.sh"

#
# Create any missing files
#
mkdir -p -m 0700 "$GEN3_WORKDIR/backups"

if [[ ! -f "$GEN3_WORKDIR/root.tf" ]]; then
  # Note: do not use `` in heredoc!
  echo "Creating $GEN3_WORKDIR/root.tf"
  cat - > "$GEN3_WORKDIR/root.tf" <<EOM
#
# THIS IS AN AUTOGENERATED FILE (by gen3)
# root.tf is required for *terraform output*, *terraform taint*, etc
# @see https://github.com/hashicorp/terraform/issues/15761
#
terraform {
    backend "s3" {
        encrypt = "true"
    }
}
EOM
fi

#
# Sync the given file with S3.
# Note that 'workon' only every copies from S3 to local,
# and only if a local copy does not already exist.
# See 'gen3 refresh' to pull down latest files from s3.
# We copy the local up to S3 at 'apply' time.
#
refreshFromS3() {
  local fileName
  local filePath
  fileName=$1
  if [[ -z $fileName ]]; then
    return 1
  fi
  filePath="${GEN3_WORKDIR}/$fileName"
  if [[ -f $filePath ]]; then
    echo "Ignoring S3 refresh for file that already exists: $fileName"
    return 1
  fi
  s3Path="s3://${GEN3_S3_BUCKET}/${GEN3_WORKSPACE}/${fileName}"
  gen3_aws_run aws s3 cp "$s3Path" "$filePath" > /dev/null 2>&1
  if [[ ! -f "$filePath" ]]; then
    echo "No data at $s3Path"
    return 1
  fi
  return 0
}

#
# Let helper generates a random string of alphanumeric characters of length $1.
#
function random_alphanumeric() {
    base64 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c $1
}


#
# Generate an initial backend.tfvars file with intelligent defaults
# where possible.
#
backend.tfvars() {
  cat - <<EOM
bucket = "$GEN3_S3_BUCKET"
encrypt = "true"
key = "$GEN3_WORKSPACE/terraform.tfstate"
region = "$(aws configure get "$GEN3_PROFILE.region")"
EOM
}

README.md() {
  cat - <<EOM
# TL;DR

Any special notes about $GEN3_WORKSPACE

## Useful commands

* gen3 help
* gen3 tfoutput ssh_config >> ~/.ssh/config
* rsync -rtvOz ${GEN3_WORKSPACE}_output/ k8s_${GEN3_WORKSPACE}/${GEN3_WORKSPACE}_output

EOM
}


#
# Generate an initial config.tfvars file with intelligent defaults
# where possible.
#
config.tfvars() {
  local commonsName

  if [[ "$GEN3_WORKSPACE" =~ _user$ ]]; then
    # user vpc is simpler ...
    cat - <<EOM
vpc_name="$GEN3_WORKSPACE"
#
# for vpc_octet see https://github.com/uc-cdis/cdis-wiki/blob/master/ops/AWS-Accounts.md
#  CIDR becomes 172.{vpc_octet2}.{vpc_octet3}.0/20
#
vpc_octet2=GET_A_UNIQUE_VPC_172_OCTET2
vpc_octet3=GET_A_UNIQUE_VPC_172_OCTET3

ssh_public_key="$(sed 's/\s*$//' ~/.ssh/id_rsa.pub)"
EOM
    return 0
  fi

  # else ...
  if [[ "$GEN3_WORKSPACE" =~ _snapshot$ ]]; then
    # rds snapshot vpc is simpler ...
    commonsName=$(echo "$GEN3_WORKSPACE" | sed 's/_snapshot$//')
    cat - <<EOM
vpc_name="${commonsName}"
indexd_rds_id="${commonsName}-indexddb"
fence_rds_id="${commonsName}-fencedb"
sheepdog_rds_id="${commonsName}-gdcapidb"
EOM
    return 0
  fi

  # else
  if [[ "$GEN3_WORKSPACE" =~ _adminvm$ ]]; then
    # rds snapshot vpc is simpler ...
    commonsName=$(echo "$GEN3_WORKSPACE" | sed 's/_snapshot$//')
    cat - <<EOM
child_account_id="ACCOUNT-ID"
child_name="NAME FOR TAGGING"
vpc_cidr_list=[ "CIDR1", "CIDR2"]
EOM
    return 0
  fi

    # else
  if [[ "$GEN3_WORKSPACE" =~ _squidvm$ ]]; then
    # rds snapshot vpc is simpler ...
    commonsName=$(echo "$GEN3_WORKSPACE" | sed 's/_snapshot$//')
    cat - <<EOM
  env_vpc_name         = "VPC-NAME"
  env_vpc_id           = "VPC-ID"
  env_vpc_cidr         = "VPC-CIDR"
  env_public_subnet_id = "VPC-PUBLIC-SUBNET"
EOM
    return 0
  fi
  
  if [[ "$GEN3_WORKSPACE" =~ _logging$ ]]; then
    # rds snapshot vpc is simpler ...
    commonsName=$(echo "$GEN3_WORKSPACE" | sed 's/_logging$//')
    cat - <<EOM
child_account_id="NUMERIC-ID"
common_name="${commonsName}"
EOM
    return 0
  fi

  # else ...
  if [[ "$GEN3_WORKSPACE" =~ _databucket$ ]]; then
    cat - <<EOM
bucket_name="$(echo "$GEN3_WORKSPACE" | sed 's/[_\.]/-/g')-gen3"
environment="$(echo "$GEN3_WORKSPACE" | sed 's/_databucket$//')"
EOM
    return 0
  fi

  if [[ "$GEN3_WORKSPACE" =~ _utilityvm ]]; then
     vmName=$(echo "$GEN3_WORKSPACE" | sed 's/_utilityvm$//')
     cat - <<EOM
bootstrap_path = "cloud-automation/flavors/"
bootstrap_script = "FILE-IN-ABOVE-PATH"
vm_name = "${vmName}"
vm_hostname = "${vmName}"
vpc_cidr_list = ["10.128.0.0/20", "52.0.0.0/8", "54.0.0.0/8"]
extra_vars = []
EOM
    return 0
  fi

  # else ...
  if [[ "$GEN3_WORKSPACE" =~ _bigdisk$ ]]; then
    cat - <<EOM
volume_size = 20
instance_ip = "10.0.0.0"
dev_name = "/dev/sdz"
EOM
    return 0
  fi

  # else ...

# ssh key to be added to VMs and kube nodes
local SSHADD=$(which ssh-add)
if [ -f ~/.ssh/id_rsa.pub ];
then
  kube_ssh_key="$(sed 's/\s*$//' ~/.ssh/id_rsa.pub)"
elif [ ! -z "$(${SSHADD} -L)" ];
then
  kube_ssh_key="$(${SSHADD} -L)"
else
  kube_ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDOHPLoBC42tbr7YiQHGRWDOZ+5ItJVhgSqAOOb8bHD65ajen1haM2PUvqCrZ0p7NOrDPFRBlNIRlhC2y3VdnKkNYSYMvHUEwt8+V3supJBj2Tu8ldzpQthDu345/Ge4hqwp+ujZVRfjjAFaFLkMtqvlAXkj7a2Ip6ZZEhd8NcRq/mQET3eCaBR5/+BGzEMBVQGTSGYOY5rOkR8PNQiX+BF7qIX/xRHo8GCOztO4KmDLmaZV63ovQwr01PXSGEq/VGfHwXAvzX13IXTYE2gechEyudhRGZBbhayyaKD7VRoKzd4BZuuUrLCSpMDWBK/qtECcP4pCXW/0Wi2OCzUen3syh/YrOtJD1CUO+VvW6/8xFrcBeoygFW87hW08ncXLT/XxpgWeExJrTGIxjr4YzcsWPBzxI7/4SmKbaDSjx/RMX7x5WbPc5AZzHY17cKcpdc14weG+sm2OoKF5RqnFB/JpBaNxG+Zq8qYC/6h8fOzDWo5+qWKO/UlWaa3ob2QpG8qOBskoyKVG3ortQ04E04DmoaOiSsXoj0U0zaJnxpdF+a0i31RxQnjckTMEHH8Y2Ow8KIG45tzhJx9NbqSj9abk3yTzGA7MHvugQFpuTQ3gaorfG+A9RGUmx6aQNwXUGu+DWRF7lFeaPJt4CDjzbDUGP/b5KJkWK0DDAI61JfOew== /home/fauzi/.ssh/id_rsa"
fi

db_password_sheepdog="$(random_alphanumeric 32)"
cat - <<EOM
# VPC name is also used in DB name, so only alphanumeric characters
vpc_name="$GEN3_WORKSPACE"
#
# for vpc_octet see https://github.com/uc-cdis/cdis-wiki/blob/master/ops/AWS-Accounts.md
#  CIDR becomes 172.{vpc_octet2}.{vpc_octet3}.0/20
#
vpc_octet2=GET_A_UNIQUE_VPC_172_OCTET2
vpc_octet3=GET_A_UNIQUE_VPC_172_OCTET3
dictionary_url="https://s3.amazonaws.com/dictionary-artifacts/YOUR/DICTIONARY/schema.json"
portal_app="dev"

aws_cert_name="YOUR.CERT.NAME"

db_size=10

hostname="YOUR.API.HOSTNAME"
#
# Bucket in bionimbus account hosts user.yaml
# config for all commons:
#   s3://cdis-gen3-users/CONFIG_FOLDER/user.yaml
#
#config_folder="PUT-SOMETHING-HERE"

google_client_secret="YOUR.GOOGLE.SECRET"
google_client_id="YOUR.GOOGLE.CLIENT"

# Following variables can be randomly generated passwords

hmac_encryption_key="$(random_alphanumeric 32 | base64)"

gdcapi_secret_key="$(random_alphanumeric 50)"

# don't use ( ) " ' { } < > @ in password
db_password_fence="$(random_alphanumeric 32)"

db_password_gdcapi="$db_password_sheepdog"
db_password_sheepdog="$db_password_sheepdog"
db_password_peregrine="$(random_alphanumeric 32)"

db_password_indexd="$(random_alphanumeric 32)"

db_instance="db.t2.micro"

# password for write access to indexd
gdcapi_indexd_password="$(random_alphanumeric 32)"

fence_snapshot=""
gdcapi_snapshot=""
indexd_snapshot=""

kube_ssh_key="${kube_ssh_key}"

kube_additional_keys = <<EOB
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDiVYoa9i91YL17xWF5kXpYh+PPTriZMAwiJWKkEtMJvyFWGv620FmGM+PczcQN47xJJQrvXOGtt/n+tW1DP87w2rTPuvsROc4pgB7ztj1EkFC9VkeaJbW/FmWxrw2z9CTHGBoxpBgfDDLsFzi91U2dfWxRCBt639sLBfJxHFo717Xg7L7PdFmFiowgGnqfwUOJf3Rk8OixnhEA5nhdihg5gJwCVOKty8Qx73fuSOAJwKntcsqtFCaIvoj2nOjqUOrs++HG6+Fe8tGLdS67/tvvgW445Ik5JZGMpa9y0hJxmZj1ypsZv/6cZi2ohLEBCngJO6d/zfDzP48Beddv6HtL rarya"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC2d7DncA3QdZoxXzkIaU4xcPZ0IJ97roh4qF3gE1dse3H/aQ5V3lYZ9HuhVYm1UnMvNvKXIdvsHUPEmwe6s9X8Fj1fxpxuF+/C6d5+5raHffEAqU/YEFa0V8vxcSCedQoiDfJwzUA7NTcMBEFAH4MdTa4hmGnlwEeW4JWFiBmr2y5UVRfrZhM+DVdv5hxFQCyTjMXz4ZOmfMnvC6W/ZNzCersDES36Mo/nqHQWIH6Xd5BfOYWrs2zW/MZRUy4Yt9hFyuKizSt77SpjmBYGeagHS0TSti36nAduMbr3dkbvPF3JhbsXxlGpZgaYR51zjK5cQNEEj2hCExWD2pWUKOzD jeff@wireles-guest-16-34-212.uchicago.edu"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw48loSG10QUtackRFsmxYXd3OezarZLuT7F+bxKYsj9rx2WEehDxg1xWESMSoHxGlHMSWpt0NMnBC2oqRz19wk3YjE/LoOaDXZmzc6UBVZo4dgItKV2+T9RaeAMkCgRcp4EsN2Rw+GNoT2whIH8jrAi2HhoNSau4Gi4zyQ2px7xBtKdco5qjQ1a6s1EMqFuOL0jqqmAqMHg4g+oZnPl9uRzZao4UKgao3ypdTP/hGVTZc4MXGOskHpyKuvorFqr/QUg0suEy6jN3Sj+qZ+ETLXFfDDKjjZsrVdR4GNcQ/sMtvhaMYudObNgNHU9yjVL5vmRBCNM06upj3RHtVx0/L rpowell@rpowell.local"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDJTr2yJtsOCsQpuKmqXmzC2itsUC1NAybH9IA3qga2Cx96+hMRLRs16vWTTJnf781UPC6vN1NkCJd/EVWD87D3AbxTF4aOKe3vh5fpsLnVI67ZYKsRl8VfOrIjB1KuNgBD1PrsDeSSjO+/sRCrIuxqNSdASBs5XmR6ZNwowF0tpFpVNmARrucCjSKqSec8VY2QneX6euXFKM2KJDsp0m+/xZqLVa/iUvBVplW+BGyPe+/ETlbEXe5VYlSukpl870wOJOX64kaHvfCaFe/XWH9uO+ScP0J/iWZpMefWyxCEzvPaDPruN+Ed7dMnePcvVB8gdX0Vf0pHyAzulnV0FNLL ssullivan@HPTemp"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDkJRaRKEl9mqTm1ZSWqO9KX3b/zl0cv6RUshS4eST42LkiLjcrH2atsh6IWnvPyy6cdG7c45ntdEEWJ9yXxMhuCKGbFyz6QIgb4h9ZDJqFtTq7w2IhqfsApXBUm6XmZJGQxzB/t96UQIP1rdV9zhkx1OT+2hIrKFiDiCY5H5skirepFjyQxfmThGl2s45ay4PDwL6Spmx3pdgJTVUijcgTff8ZAnARpDJTeVWc/oGZtRG68+/iaVisGnDEVrt2YaQek0p8bTVSuiLGoZ/RC0luoBSdBvrPgU+UKOQXpqTwdZWOug6v/yInwROAKUvElD6AOoJbXLnbhzG78llD47CP kyle@Kyles-MacBook-Pro.local"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYe74TEoKYZm9cfCTAsjICaKUzAkh3/Y6mhzhhzYIqra0J5efQ+SJcDt7soOJ2qE1zOcGGvuA8belebkjOZDv50Mn5cEvaKsbpS9Poq0H02TzKby42pfV4TER1XbByuHC9eltsbn7efnmsdzcaY4uv2bMVXVauO0/XwHgoatVAeKvc+Gwkgx5BqiSI/MY+qDpldufL6f0hzsxFVlC/auJp+NWmKDjfCaS+mTBEezkXlg04ARjn3Pl68troK2uP2qXNESFgkBDTsLftM6p8cKIGjVLZI2+D4ayjbRbKWNQxS3L5CEeobzrovtls5bPSbsG/MxFdZC6EIbJH5h/6eYYj"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCk0Z6Iy3mhEqcZLotIJd6j0nhq1F709M8+ttwaDKRg11kYbtRHxRv/ATpY8PEaDlaU3UlRhCBunbKhFVEdMiOfyi90shFp/N6gKr3cIzc6GPmobrSmpmTuHJfOEQB1i3p+lbEqI1aRj9vR/Ug/anjWd2dg+VBIi4kgX1hKVrEd1CHxySRYkIo+NTTwzglzEmcmp+u63sLjHiHXU055H5D6YwL3ussRVKw8UePpTeGO3tD+Y0ogyqByYdQWWTHckTwuvjIOTZ9T5wvh7CPSXT/je6Ddsq5mRqUopvyGKjHWaxO2s7TI9taQAvISE9rH5KD4hceRa81hzu3ZqZRw4in8IuSw5r8eG4ODjTEl0DIqa0C+Ui+MjSkfAZki0DjBf/HJbWe0c06MEJBorLjs9DHPQ5AFJUQqN7wk29r665zoK3zBdZG/JDXccZmptSMKVS02TxxzAON7oG66c9Kn7Vq6MBYcE3Sz7dxydm6PtvFIqij9KTfJdE+yw2o9seywB5yFfPkL63+hYZUaDFeJvvQSq5+7X2Cltn+F05J+EiORU5wO5oQWV01a2Yf6RT3o/728aYfaPjkdubwbCDWkdo8FaRqmK1NdQ8IoFprBjrhyDFwIXMEuVPrCJOUjL+ksXLPvYw2truiPfDxWxcvkVOAl4myfQOP4YqGmQ/IumYUbAw== thanhnd@uchicago.edu"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC6vuAdqy0pOwC5rduYmnjHTUsk/ryt//aJXwdhsFbuEFxKyuHsZ2O9r4wqwqsVpHdQBh3mLPXNGo2MZFESNEoL1olzW3VxXXzpujGHDd/F9FmOpnAAFz90gh/TM3bnWLLVWF2j7SKw68jUgijc28SnKRNRXpKJLv6PN9qq8OMHaojnEzrsGMb69lMT8dro1Yk71c4z5FDDVckN9UVL7W03+PE/dN6AtNWMlIEWlgm6/UA9Og+w9VYQnhEylxMpmxdO0SAbkIrr3EPC16kRewfovQLZJsw2KRo4EK62Xyjem/M1nHuJo4KpldZCOupxfo6jZosO/5wpKF1j8rF6vPLkHFYNwR62zTrHZ58NVjYTRF927kW7KHEq0xDKSr5nj9a8zwDInM/DkMpNyme4Jm3e4DOSQ3mP+LYG9TywNmf9/rVjEVwBBxqGRi27ex6GWcLm4XB58Ud3fhf5O5BDdkLYD1eqlJE5M4UG5vP5C9450XxW5eHUi/QK2/eV+7RijrEtczlkakPVO7JdWDZ44tX9sjkAlLSvgxkn4xZSdfqm/aJBIHUpoEitkZf9kgioZdDz2xmBDScG3c3g5UfPDrMvSTyoMliPo7bTIjdT/R1XV27V8ByrewwK/IkS70UkbIpE3GNYBUIWJBdNPpgjQ5scMOvhEIjts2z4KKq1mUSzdQ== zac"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfX+T2c3+iBP17DS0oPj93rcQH7OgTCKdjYS0f9s8sIKjErKCao0tRNy5wjBhAWqmq6xFGJeA7nt3UBJVuaGFbszIzs+yvjZYYVrJQdfl0yPbrKRMd/Ch77Jnqbu97Uyu8UxhGkzqEcxQrdBqhqkakhQULjcjZBnk0M1PrLwW+Pl1kRCnXnX/x3YzDR/Ltgjc57qjPbqz7+CBbuFo5OCYOY94pcXetHskvx1AAQ7ZT2c/F/p6vIH5jPKnCTjuqWuGoimp/alczLMO6n+aHgzqc9NKQUScxA0fCGxFeoEdd6b370E7j8xXMIA/xSmq8lFPam+fm3117nC4m29sRktoBI8YP4L7VPSkM/hLp/vRzVJf6U183GfvUSZPERrg+NvMeah9vgkTgzH0iN1+s2xPj6eFz7VUOQtLYTchMZ/qyyGhUzJznY0szocVd6iDbMAYm67R+QtgYEBD1hYrtUD052imb62nEXHFSL3V6369GaJ+k5BIUTGweOaUxGbJlb6fG2Aho4EWaigYRMtmlKgDFaCeJGjlQrFR9lKFzDBc3Af3RefPDVsavYGdQQRUAmueGjlks99Bvh2U53HQgQvc0iQg3ijey2YXBr6xFCMeG7MJZbPcrlQLXko4KygK94EcDPZnIH542CrtAySk/UxxwZv5u0dLsh7o+ZK9G6PO1+Q== reubenonrye@uchicago.edu"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCi6uv+jsUNpMXgP0CL2XZa5YgFFpoFj3vu7rCpKTvsCRoxfR/piv8PXIAlFCWLDOHb/jn1BBl+RuYDv74PcCac9sb97HKTstEE6M0aHjvYtHr1po5GSTXNHqILSmypDaafLr30nWRd2GymFUZbIFRfrcbzVn9K+DQ9Hkny5yvrra4OD+rhGHettUWOszxfFRVBpBHKNy87rKQbFcyYlnrNHwifInmNLA+sPkbuvx6Cvra7EoTPfsc04z1QyVKiN4IqyKrJnTO3adS3z+EoMHw7xEVvX7dVX9I8Fl095IL2mtH0FEpT89OcGzVLnM72NszFZMksNsi9i4By/FELT3zN rudyardrichter@socrates.local"'
  - '"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDOHPLoBC42tbr7YiQHGRWDOZ+5ItJVhgSqAOOb8bHD65ajen1haM2PUvqCrZ0p7NOrDPFRBlNIRlhC2y3VdnKkNYSYMvHUEwt8+V3supJBj2Tu8ldzpQthDu345/Ge4hqwp+ujZVRfjjAFaFLkMtqvlAXkj7a2Ip6ZZEhd8NcRq/mQET3eCaBR5/+BGzEMBVQGTSGYOY5rOkR8PNQiX+BF7qIX/xRHo8GCOztO4KmDLmaZV63ovQwr01PXSGEq/VGfHwXAvzX13IXTYE2gechEyudhRGZBbhayyaKD7VRoKzd4BZuuUrLCSpMDWBK/qtECcP4pCXW/0Wi2OCzUen3syh/YrOtJD1CUO+VvW6/8xFrcBeoygFW87hW08ncXLT/XxpgWeExJrTGIxjr4YzcsWPBzxI7/4SmKbaDSjx/RMX7x5WbPc5AZzHY17cKcpdc14weG+sm2OoKF5RqnFB/JpBaNxG+Zq8qYC/6h8fOzDWo5+qWKO/UlWaa3ob2QpG8qOBskoyKVG3ortQ04E04DmoaOiSsXoj0U0zaJnxpdF+a0i31RxQnjckTMEHH8Y2Ow8KIG45tzhJx9NbqSj9abk3yTzGA7MHvugQFpuTQ3gaorfG+A9RGUmx6aQNwXUGu+DWRF7lFeaPJt4CDjzbDUGP/b5KJkWK0DDAI61JfOew== fauzi@uchicago.edu"'
EOB
EOM
}

for fileName in config.tfvars backend.tfvars README.md; do
  filePath="${GEN3_WORKDIR}/$fileName"
  if [[ ! -f "$filePath" ]]; then
    refreshFromS3 "$fileName"
    if [[ ! -f "$filePath" ]]; then
      echo "Variables not configured at $filePath"
      echo "Setting up initial contents - you must customize the file before running terraform"
      # Run the function that corresponds to $fileName
      $fileName > "$filePath"
    fi
  fi
done

cd "$GEN3_WORKDIR"
bucketCheckFlag=".tmp_bucketcheckflag2"
if [[ ! -f "$bucketCheckFlag" ]]; then
  echo "initializing terraform"
  echo "checking if $GEN3_S3_BUCKET bucket exists"
  if ! gen3_aws_run aws s3 ls "s3://$GEN3_S3_BUCKET" > /dev/null 2>&1; then
    echo "Creating $GEN3_S3_BUCKET bucket"
    echo "NOTE: please verify that aws profile region matches backend.tfvars region:"
    echo "  aws profile region: $(aws configure get $GEN3_PROFILE.region)"
    echo "  terraform backend region: $(cat *backend.tfvars | grep region)"

    S3_POLICY=$(cat - <<EOM
  {
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }
EOM
)
    gen3_aws_run aws s3api create-bucket --acl private --bucket "$GEN3_S3_BUCKET"
    sleep 5 # Avoid race conditions
    if gen3_aws_run aws s3api put-bucket-encryption --bucket "$GEN3_S3_BUCKET" --server-side-encryption-configuration "$S3_POLICY"; then
      touch "$bucketCheckFlag"
    fi
  else
    touch "$bucketCheckFlag"
  fi
fi

echo "Running: terraform init --backend-config ./backend.tfvars $GEN3_TFSCRIPT_FOLDER/"
gen3_aws_run terraform init --backend-config ./backend.tfvars "$GEN3_TFSCRIPT_FOLDER/"

# Generate some k8s helper scripts for on-prem deployments
if ! [[ "$GEN3_WORKSPACE" =~ _user$ || "$GEN3_WORKSPACE" =~ _snapshot$ || "$GEN3_WORKSPACE" =~ _adminvm$ || "$GEN3_WORKSPACE" =~ _databucket$ || "$GEN3_WORKSPACE" =~ _logging$  || "$GEN3_WORKSPACE" =~ _squidvm$ || "$GEN3_WORKSPACE" =~ _utilityvm$ ]]; then
  mkdir -p -m 0700 onprem_scripts
  cat - "$GEN3_HOME/tf_files/configs/kube-services-body.sh" > onprem_scripts/kube-services.sh <<EOM
#!/bin/bash
#
# Terraform template concatenated with kube-services.sh and kube-up.sh in kube.tf
#

set -e

vpc_name='${GEN3_WORKSPACE}'

EOM

  if [[ ! -f onprem_scripts/creds.json ]]; then
    cat "$GEN3_HOME/tf_files/configs/creds.tpl" > onprem_scripts/creds.json
  else
    echo "onprem_scripts/creds.json already exists ..."
  fi
  if [[ ! -f onprem_scripts/00configmap.yaml ]]; then
    cat "$GEN3_HOME/tf_files/configs/00configmap.yaml" > onprem_scripts/00configmap.yaml
  else
    echo "onprem_scripts/00configmap.yaml already exists ..."
  fi
  if [[ ! -f onprem_scripts/README.md ]]; then
    cat - > onprem_scripts/README.md <<EOM
# TL;DR

This folder contains scripts intended to help bootstrap gen3 k8s services
in an on-prem k8s cluster.  The scripts are auto-generated by *gen3 workon*, and can
take the place of the scripts that terraform generates under *VPCNAME_output/*
for AWS commons deployments.

# On prem process

Something like the following should work to bootstrap an on prem commons:

* Configure the variables in *onprem_scripts/creds.json* and *onprem_scripts/00configmap.yaml*,
  and verify that *onprem_scripts/kube-services.sh* sets the right *vpc_name* at the top of the script.
* *rsync onprem_scripts/ bastion.host:{VPC_NAME}_output/*
* ssh to bastion.host, and verify that *kubectl* works - ex: *kubectl get nodes*
* *cd {VPC_NAME}_output && bash kube-services.sh*
EOM
  fi
fi
