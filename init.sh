#!/usr/bin/env bash

REPO_DIR=$(dirname "$0")
ENV_FILE="${REPO_DIR}/.env"

if [ ! -f $ENV_FILE ]; then
  echo "ERROR: \".env\" file not detected."; exit
fi

source $ENV_FILE
echo "INFO: Environment file detected."

DOMAIN_NAME=${DOMAIN_NAME:-localhost}
HTTP_PORT=$([ ${NGINX_HTTP_PORT:-80} == 80 ] && echo "" || echo :${NGINX_HTTP_PORT})
HTTPS_PORT=$([ ${NGINX_HTTPS_PORT:-443} == 443 ] && echo "" || echo :${NGINX_HTTPS_PORT})

# Clean install
rm -rf ${REPO_DIR}/core

# HTTP by default
cp ${REPO_DIR}/config/nginx/templates/http.conf ${REPO_DIR}/config/nginx/default.conf

# Map DOMAIN_NAME to 127.0.0.1
echo "INFO: Adding \"127.0.0.1 ${DOMAIN_NAME}\" entry on /etc/hosts."
grep -qxF '127.0.0.1 '${DOMAIN_NAME} /etc/hosts || echo "127.0.0.1 ${DOMAIN_NAME}" | sudo tee -a /etc/hosts

# If NOT macOS EXIT
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "INFO: WordPress installed on \"http://${DOMAIN_NAME}${HTTP_PORT}\"\nRUN > docker-compose up -d --build"
    exit 0;
fi

###################################
# Some crazy magic for macOS only #
###################################

# Trusted self-signed certificates automatically
echo "INFO: macOS detected!"

DOMAIN_CERTS_DIR="${REPO_DIR}/${CERTS_DIR:-certs}/dev/${DOMAIN_NAME}"
if [ ! -d "${DOMAIN_CERTS_DIR}" ]; then
    mkdir -p ${DOMAIN_CERTS_DIR}
fi

# HTTPS by default
cp ${REPO_DIR}/config/nginx/templates/https.conf ${REPO_DIR}/config/nginx/default.conf

# Generate openssl.cnf file
cat "/System/Library/OpenSSL/openssl.cnf" > ${DOMAIN_CERTS_DIR}/openssl.cnf
printf '[SAN]\nsubjectAltName=DNS:'${DOMAIN_NAME} >> ${DOMAIN_CERTS_DIR}/openssl.cnf 

# Generate self-signed certificates
openssl req \
    -newkey rsa:2048 \
    -x509 \
    -nodes \
    -keyout ${DOMAIN_CERTS_DIR}/privkey.pem \
    -new \
    -out ${DOMAIN_CERTS_DIR}/fullchain.pem \
    -subj /CN=\*.${DOMAIN_NAME} \
    -reqexts SAN \
    -extensions SAN \
    -config ${DOMAIN_CERTS_DIR}/openssl.cnf \
    -sha256 \
    -days 3650 \
    > /dev/null 2>&1

echo "INFO: Self-signed certificates generated!"

#mv fullchain.pem ${DOMAIN_CERTS_DIR}/
#mv privkey.pem ${DOMAIN_CERTS_DIR}/
rm -f ${DOMAIN_CERTS_DIR}/openssl.cnf

# Trust self-signed certificate
echo "INFO: Adding trusted certificates to Keychain ..."
if [ $(security dump-keychain | grep "${DOMAIN_NAME}" | wc -l | awk '{print $1}') -gt 0 ]; then
    sudo security delete-certificate -c ${DOMAIN_NAME}
fi
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${DOMAIN_CERTS_DIR}/fullchain.pem

echo "INFO: WordPress installed on https://${DOMAIN_NAME}${HTTPS_PORT}\nRUN > docker-compose up -d --build"

exit 0;