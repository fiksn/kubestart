#!/bin/bash
set -eu

export CURL=${CURL:-"curl --connect-timeout 5"}
export KUBE_MASTER=${KUBE_MASTER:-"https://10.200.24.254:443"}
export DIR=${DIR:-"$HOME/.kube"}
export CFSSL_VER=${CFSSL_VER:-"R1.2"}
export DISTRO=${DISTRO-"$(uname -s | tr '[:upper:]' '[:lower:]')"}
export BIN_DIR=${BIN_DIR:-"/usr/local/bin"}
export SUDO=${SUDO:-"sudo"}
export LONG_WAIT=${LONG_WAIT:-"300"}
export SHORT_WAIT=${SHORT_WAIT:-"60"}

if [ -z ${ARCH+x} ]; then
  case $(uname -m) in
    x86_64)
        ARCH="amd64" ;;
    i686)
        ARCH="386" ;;
    arm)
        ARCH="arm" ;;
    *)
      echo "Architecture $(uname -m) not supported, override ARCH variable"
  esac
fi

command_exists () {
  set +e
  MSG=$1
  shift 1
  "$@" > /dev/null 2>/dev/null
  if [ $? -eq 127 ]; then
    echo "$MSG"
    exit 1
  fi
  set -e
}

install_cfssl () {
  echo "Installing cfssl..."
  $SUDO $CURL --max-time ${LONG_WAIT} https://pkg.cfssl.org/${CFSSL_VER}/cfssl_${DISTRO}-${ARCH} -o ${BIN_DIR}/cfssl || exit 1
  echo "Installing cfssljson..."
  $SUDO $CURL --max-time ${LONG_WAIT} https://pkg.cfssl.org/${CFSSL_VER}/cfssljson_${DISTRO}-${ARCH} -o ${BIN_DIR}/cfssljson || exit 1
  $SUDO chmod a+x ${BIN_DIR}/cfssl
  $SUDO chmod a+x ${BIN_DIR}/cfssljson
}

install_kubectl () {
    echo "Installing kubectl..."
    $SUDO $CURL --max-time ${LONG_WAIT} -o ${BIN_DIR}/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${DISTRO}/${ARCH}/kubectl || exit 1
    $SUDO chmod a+x ${BIN_DIR}/kubectl
}

install_ca () {
  $CURL --max-time ${SHORT_WAIT} -o "${DIR}/ca.pem" https://raw.githubusercontent.com/fiksn/kubestart/master/ca.pem 2>/dev/null
}

verify_commands () {
  command_exists "You do not seem to have curl installed - try 'apt-get install curl'" $CURL
  command_exists "You do not seem to have jq installed - try 'brew install jq' or 'apt-get install jq'" jq
  command_exists "You do not seem to have sudo installed - try 'apt-get install sudo'" $SUDO id

  cfssl version >/dev/null 2>/dev/null || install_cfssl
}

create_csr () {
  if [ ! -f "${ESCAPED_USER}.csr" ]; then
    echo "Creating CSR..."
    cat <<EOF | cfssl genkey - 2>/dev/null | cfssljson -bare $ESCAPED_USER 2>/dev/null || exit 1
{
  "CN": "$ESCAPED_USER",
  "key": {
    "algo": "ecdsa",
    "size": 256
  }
}
EOF
  fi

  echo "Creating certficate request..."
  RESULT=$(cat <<EOF | $CURL --max-time ${SHORT_WAIT} --cacert "${DIR}/ca.pem" -X POST --data-binary @/dev/stdin  -H "Content-Type: application/yaml" -H "Accept: application/json" ${KUBE_MASTER}/apis/certificates.k8s.io/v1beta1/certificatesigningrequests 2>/dev/null | jq '.status' | tr -d '"'
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: ${ESCAPED_USER}
spec:
  groups:
  - system:authenticated
  request: $(cat ${ESCAPED_USER}.csr | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF
  )

  if [ "$RESULT" != "{}" ]; then
    echo "Server returned failure"
    exit 1
  fi

  mv -f "${ESCAPED_USER}-key.pem" "${DIR}/${ESCAPED_USER}.key"
  rm -f "${ESCAPED_USER}.csr"
}

create_conf () {
  echo "Initalizing kube configuration..."

  if [ -f "${DIR}/config" ]; then
    mv -f "${DIR}/config" "${DIR}/config.backup.$$"
  fi

  cat <<EOF > "${DIR}/config"
apiVersion: v1
clusters:
- cluster:
    certificate-authority: ./ca.pem
    server: https://mts-dev-k8s.sportradar.ag:6443
  name: dev
- cluster:
    certificate-authority: ./ca.pem
    server: https://10.200.24.254:443
  name: prod
- cluster:
    certificate-authority: ./ca.pem
    server: https://10.200.25.254:443
  name: stg
contexts:
- context:
    cluster: stg
    namespace: market-mapping
    user: user
  name: market-mapping
- context:
    cluster: stg
    namespace: ci
    user: user
  name: ci
- context:
    cluster: dev
    user: user
  name: dev
- context:
    cluster: dev
    namespace: system-test
    user: user
  name: devtst
- context:
    cluster: dev
    namespace: fiction
    user: user
  name: fiction
- context:
    cluster: prod
    user: user
  name: prod
- context:
    cluster: stg
    namespace: replay
    user: user
  name: replay
- context:
    cluster: prod
    namespace: replay
    user: user
  name: replay2
- context:
    cluster: dev
    namespace: rtop-dev
    user: user
  name: rtop-dev
- context:
    cluster: stg
    namespace: rtop-stg
    user: user
  name: rtop-stg
- context:
    cluster: prod
    namespace: rtop-prod
    user: user
  name: rtop-prod
- context:
    cluster: stg
    user: user
  name: stg
- context:
    cluster: stg
    namespace: system-test
    user: user
  name: stgtst
current-context: dev
kind: Config
preferences:
  colors: true
users:
- name: user
  user:
    client-certificate: ./${ESCAPED_USER}.crt
    client-key: ./${ESCAPED_USER}.key
EOF
}

# If I was sourced
set +e
return 2>/dev/null
set -e

if [ "$#" -gt 0 ]; then
  KUBE_USER=${KUBE_USER:-"$1"}
fi

if [ -z ${KUBE_USER+x} ]; then
  read -r -p "What is your username? (example: a.user)> " KUBE_USER
fi

if [ -z ${KUBE_USER+x} ]; then
  echo "Invalid user"
  exit 1
fi

verify_commands

ESCAPED_USER=$(echo $KUBE_USER | tr -cd "[a-z]")

echo "Hello ${ESCAPED_USER}"

if [ ! -x "${BIN_DIR}/kubectl" ]; then
  install_kubectl
fi

mkdir -p "${DIR}"

install_ca
create_csr
create_conf

$CURL -o "$DIR/cert.sh" https://raw.githubusercontent.com/fiksn/kubestart/master/cert.sh 2>/dev/null || exit 1
chmod a+x "$DIR/cert.sh"

echo "Somebody with the privilege now needs to do \"kubectl certificate approve ${ESCAPED_USER}\" and give you the correct role through RBAC"
echo "Afterwards you need to run ${DIR}/cert.sh to obtain the signed certificate"
