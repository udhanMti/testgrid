#!/bin/bash

# This script is responsible for creating a Docker Image of the given Product with WUM updates and
# Pushing it to the Private Docker registry

set -o xtrace
alias wget='wget -q'
alias unzip='unzip -q'

LOG_FILE="" # log.txt
GIT_REPO_ZIP_URL=""
PRODUCT_NAME="" # wso2is
WSO2_SERVER_VERSION="" # 5.3.0
GIT_REPO_NAME="" # docker-is-master
DOCKERFILE_DIR=""
TAG=""

MYSQL_CONNECTOR_URL="http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar"
ORACLE_JDBC_URL="http://download.oracle.com/otn/utilities_drivers/jdbc/183/ojdbc8.jar"
MSSQL_JDBC_URL="http://central.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/7.0.0.jre8/mssql-jdbc-7.0.0.jre8.jar"
POSTGRESQL_URL="https://jdbc.postgresql.org/download/postgresql-42.2.5.jar"

ORACLE_JDK_URL="http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.tar.gz"

WUM_CONFIG_FILE=~/.wum3/config.yaml; WUM_TMP="wum_conf.tmp";


# Use default if not stored as environment variables
if [ -z $(echo $SERVICE_ACCOUNT) ]; then SERVICE_ACCOUNT="gke-bot@testgrid.iam.gserviceaccount.com"; fi
if [ -z $(echo $CLUSTER_NAME) ]; then CLUSTER_NAME="chathurangi-test-cluster";fi
if [ -z $(echo $ZONE) ]; then ZONE="us-central1-a"; fi
if [ -z $(echo $PROJECT_NAME) ]; then PROJECT_NAME="testgrid"; fi
if [ -z $(echo $REG_LOCATION) ]; then REG_LOCATION="asia.gcr.io"; fi
if [ -z $(echo $PROJECT_ID) ]; then PROJECT_ID="testgrid/wso2-docker"; fi


while (( "$#" )); do
  case "$1" in
    --log-file)
      LOG_FILE=$2
      shift 2
      ;;
    --git-repo-zip-url)
      GIT_REPO_ZIP_URL=$2
      shift 2
      ;;
    --product-name)
      PRODUCT_NAME=$2
      shift 2
      ;;
    --wso2-server-version)
      WSO2_SERVER_VERSION=$2
      shift 2
      ;;
    --git-repo-name)
      GIT_REPO_NAME=$2
      shift 2
      ;;
    --docker-file-dir)
      DOCKERFILE_DIR=$2
      shift 2
      ;;
    --tag)
      TAG=$2
      shift 2
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Unsupported input !"
      ;;
  esac
done


PRODUCT="${PRODUCT_NAME}-${WSO2_SERVER_VERSION}"
PRODUCT_NAME_ZIP="${PRODUCT}.zip"
WUM_DIR="${HOME}/.wum3/products/${PRODUCT_NAME}/${WSO2_SERVER_VERSION}"
WSO2_FULL_CHANNEL_DIR="${WUM_DIR}/full"
WSO2_PRODUCT_PACK="${WUM_DIR}/${PRODUCT_NAME_ZIP}"
WSO2_PRODUCT_BASE_ZIP=${WSO2_PRODUCT_PACK}
DOCKERFILE_HOME="${GIT_REPO_NAME}/dockerfiles/${DOCKERFILE_DIR}"

# TODO: CAN BE REMOVED
ZIP_FILE_NAME="master.zip"
JDK_FILE="jdk-8u*-linux-x64.tar.gz"

function log_info() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')][INFO]: $@" >&1 | tee -a ${LOG_FILE}
}

function log_error() {
    local err_msg=$@
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')][ERROR]: ${err_msg}" >&2 | tee -a ${LOG_FILE}
    exit 1
}

function get_pack_timestamp() {
local file_name=$(basename "$1")
local file_name_without_ext="${file_name%.*}"
local file_name_without_channel="${file_name_without_ext%.*}"
local time_stamp="${file_name_without_channel##*+}"
echo ${time_stamp}
}

function install_dependencies() {

  cd ../$INSTALLMENT

  if [ ! $(which gcloud) ]; then
    log_info "Gcloud is not confiured ! Configuring Gcloud."

    if [ ! -f google-cloud-sdk-247.0.0-linux-x86_64.tar.gz ]; then
      wget https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-247.0.0-linux-x86_64.tar.gz
    fi

    if ! tar -xzf google-cloud-sdk-247.0.0-linux-x86_64.tar.gz; then
      log_error "Could not extract google-cloud-sdk-247.0.0-linux-x86_64.tar.gz"
    fi
    log_info "google-cloud-sdk-247.0.0-linux-x86_64.tar.gz is successfully extracted"

    if ! ./google-cloud-sdk/install.sh; then
      log_error "Could not install gcloud"
    fi
    log_info "gcloud is successfully installed."

    source google-cloud-sdk/path.bash.inc
    source google-cloud-sdk/completion.bash.inc

    gcloud auth configure-docker

    gcloud auth activate-service-account --key-file=key.json
    gcloud config set account $SERVICE_ACCOUNT
    gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_NAME
  fi

  if [ ! $(which wum) ]; then
    log_info "WUM is not configured! Configuring WUM."
    #rm -r ~/.wum3
    if [ ! -f wum-3.0.5-linux-i586.tar.gz ]; then
      wget --https-only http://product-dist.wso2.com/downloads/wum/3.0.5/wum-3.0.5-linux-i586.tar.gz
    fi

    if ! sudo tar -C /usr/local -xzf wum-3.0.5-linux-i586.tar.gz; then
      log_error "Cannot extract wum-3.0.5-linux-i586.tar.gz"
    fi
    log_info "wum-3.0.5-linux-i586.tar.gz is extracted successfully."
    export PATH=$PATH:/usr/local/wum/bin

    if ! wum init -u ${WUM_USERNAME} -p ${WUM_PASSWORD}; then
      log_error "WUM initiation failed."
    fi

  fi

  cd ../${WORKSPACE}

}
#wum temp ---> new filw
#output -file/input file === wum config directory
function config_uat(){

  cat $WUM_CONFIG_FILE

  if ! cat ${WUM_CONFIG_FILE} | grep -q "uat"; then
    echo "ok"

    cp $WUM_CONFIG_FILE $WUM_TMP
    sed -i.bak 's/: true/: false/g' $WUM_TMP

    line_end=$(cat $WUM_TMP | wc -l); bottom_conf="";

    if cat ${WUM_TMP} | grep -q "products:"; then
      line_product=$(awk '/products:/{ print NR; exit }' $WUM_TMP);
      top_count=`expr $line_product - 1`
      top_conf=$(head -n $top_count $WUM_TMP)
      bottom_count=`expr $line_end - $line_product + 1`
      bottom_conf=$(tail -n $bottom_count $WUM_TMP)
    else
      top_conf=$(head -n `expr $line_end` ${WUM_TMP})
    fi

    echo "${top_conf}" > ${WUM_CONFIG_FILE}

  cat >> $WUM_CONFIG_FILE << EOF
  uat:
    enabled: true
    name: WSO2 UAT Repository
    url: ${UAT_URL}
    tokenurl: https://api.updates.wso2.com/token
    appkey: ${UAT_APPKEY}
    refreshtoken:
    accesstoken:
EOF

    echo "${bottom_conf}" >> ${WUM_CONFIG_FILE}

    rm $WUM_TMP
    rm "$WUM_TMP.bak"
   fi
     cat $WUM_CONFIG_FILE
}

function get_wum_update() {

    wum init -u ${WUM_USERNAME} -p ${WUM_PASSWORD}

    if ! $(wum list | grep -q ${PRODUCT}) ; then
       log_info "${PRODUCT} is not configured !."
       if ! wum add --assumeyes -v ${PRODUCT} ; then
           log_error "Cannot add ${PRODUCT} to the WUM"
          else
           log_info "${PRODUCT} is added to WUM !"
       fi
    fi

    log_info "Get WUM updates..."
    if ! wum update ${PRODUCT} ; then
        log_error "WUM update failed for ${PRODUCT}"
    fi
}

function get_latest_pack() {
  # if no full channel folder exists, take GA pack
  # else, select the pack with latest timestamp
  if test -d ${WSO2_FULL_CHANNEL_DIR}; then
      local -a update_packs=(${WSO2_FULL_CHANNEL_DIR}/*)
      local index=0
      local latest_time_stamp=0
      for ((i=0; i < ${#update_packs[@]}; i++)); do
          current_time_stamp=$(get_pack_timestamp ${update_packs[$i]})
          if [ ${current_time_stamp} -gt ${latest_time_stamp} ] ; then
              latest_time_stamp=${current_time_stamp}
              index=${i}
          fi
      done

      # change the global variable
      WSO2_PRODUCT_PACK=${update_packs[${index}]}
  fi
}

function copy_dependencies() {

if ! unzip -q -n  ${WSO2_PRODUCT_PACK} -d ${DOCKERFILE_HOME}files/; then
log_error " cannot unzip  ${WSO2_PRODUCT_PACK}  to ${DOCKERFILE_HOME}files/"
fi
log_info "${WSO2_PRODUCT_PACK} is extracted to ${DOCKERFILE_HOME}files/"

# Download JDK

if ! wget --https-only -c --header "Cookie: oraclelicense=accept-securebackup-cookie" ${ORACLE_JDK_URL} ; then
  log_error "Cannot download Oracle JDK"
fi

if ! tar -xf ${JDK_FILE} -C ${DOCKERFILE_HOME}files/ ; then
log_error "Cannot extract  ${JDK_FILE} to ${DOCKERFILE_HOME}files/"
fi
log_info "${JDK_FILE} is extracted to ${DOCKERFILE_HOME}files/"

# Download JDBC drivers
if ! wget --https-only -P ${DOCKERFILE_HOME}files/ ${MYSQL_CONNECTOR_URL}; then
    log_error "Cannot download MySQL connector"
fi
log_info "MySQL Connector is extracted to ${DOCKERFILE_HOME}files/"
if ! wget --https-only -P ${DOCKERFILE_HOME}files/ ${MSSQL_JDBC_URL}; then
    log_error "Cannot download MSSQL JDBC Driver"
fi
log_info "MSSQL JDBC Driver is extracted to ${DOCKERFILE_HOME}files/"
if ! wget --https-only -P ${DOCKERFILE_HOME}files/ ${POSTGRESQL_URL}; then
    log_error "Cannot download PostgreSQL JDBC Driver"
fi
log_info "PostgreSQL JDBC Driver is extracted to ${DOCKERFILE_HOME}files/"
if ! wget --https-only --user ${ORACLE_USER} --password ${ORACLE_PASS}  -P ${DOCKERFILE_HOME}files/ ${ORACLE_JDBC_URL}; then
    log_error "Cannot download PostgreSQL JDBC Driver"
fi
log_info "Oracle JDBC Driver is extracted to ${DOCKERFILE_HOME}files/"

}

function build_push_docker_image() {

    log_info "Build the Docker Image. Docker file location: ${DOCKERFILE_HOME}"
    if ! docker build -t ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:${WSO2_SERVER_VERSION}  ${DOCKERFILE_HOME} ; then
        log_error "Docker Image \"${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:${WSO2_SERVER_VERSION}\" building is failed. Docker file location: ${DOCKERFILE_HOME}"
    fi
    log_info "Docker image building for ${PRODUCT} is successful !."

    log_info "Pushing the Docker Image: ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:${WSO2_SERVER_VERSION} to Registry: ${REG_LOCATION}/${PROJECT_ID}"
    if ! docker push ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:${WSO2_SERVER_VERSION}; then
        log_error "${PRODUCT} Docker Image \"${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:${WSO2_SERVER_VERSION}\" pushing is failed. Docker file location: ${DOCKERFILE_HOME}"
    fi
    if ! docker tag ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:${WSO2_SERVER_VERSION}  ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:latest ; then
        log_error "Docker Image \"${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:latest\" tagging is failed. Docker file location: ${DOCKERFILE_HOME}"
    fi
    log_info "Docker image tagging with \"latest\" for ${PRODUCT} is successful !."

    log_info "Pushing the Docker Image: ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:latest to Registry: ${REG_LOCATION}/${PROJECT_ID}"
    if ! docker push ${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:latest; then
        log_error "${PRODUCT} Docker Image \"${REG_LOCATION}/${PROJECT_ID}/${PRODUCT_NAME}:latest\" pushing is failed. Docker file location: ${DOCKERFILE_HOME}"
    fi

    log_info "${PRODUCT} Docker image is pushed successfully !."

}

function download_docker_repo() {
  log_info "Downloading the Git repo: ${GIT_REPO_ZIP_URL}"

  if [ -z "${ACCESS_TOKEN}" ]; then
      if ! wget --https-only ${GIT_REPO_ZIP_URL} -O ${ZIP_FILE_NAME}; then
          log_error "WGET failed to download the Git repo ${GIT_REPO_ZIP_URL}"
      fi
  else
      if ! curl -H "Authorization: token ${ACCESS_TOKEN}" -H 'Accept: application/vnd.github.v3.raw' -o ${ZIP_FILE_NAME} -L ${GIT_REPO_ZIP_URL}; then
       log_error "Curl failed to download the Git repo: ${GIT_REPO_ZIP_URL}. Exiting !!"
      fi
  fi

  if ! unzip -q ${ZIP_FILE_NAME};then
      log_error "Cannot unzip ${ZIP_FILE_NAME}"
  fi

  log_info "\"${ZIP_FILE_NAME}\" is extracted !"

}

install_dependencies

config_uat

download_docker_repo

get_wum_update
get_latest_pack
copy_dependencies

build_push_docker_image
