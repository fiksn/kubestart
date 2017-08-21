#!/bin/sh

export CURL=${CURL:-"curl --connect-timeout 5 --max-time 10"}
export KUBE_MASTER=${KUBE_MASTER:-"https://10.27.26.98:443"}
export DIR=${DIR:-"$HOME/.kube"}
export CFSSL_VER=${CFSSL_VER:-"R1.2"}
export DISTRO=${DISTRO-"$(uname -s | tr '[:upper:]' '[:lower:]')"}
export BIN_DIR=${BIN_DIR:-"/usr/local/bin"}
export SUDO=${SUDO:-"sudo"}

if [ -z "$ARCH" ]; then
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
  MSG=$1
  shift 1
  "$@" > /dev/null 2>/dev/null
  if [ $? -eq 127 ]; then
    echo "$MSG"
    exit 1
  fi
}

install_cfssl () {
  $SUDO $CURL https://pkg.cfssl.org/${CFSSL_VER}/cfssl_${DISTRO}-${ARCH} -o ${BIN_DIR}/cfssl
  $SUDO $CURL https://pkg.cfssl.org/${CFSSL_VER}/cfssljson_${DISTRO}-${ARCH} -o ${BIN_DIR}/cfssljson
  $SUDO chmod a+x ${BIN_DIR}/{cfssl,cfssljson}
}

command_exists "You do not seem to have curl installed - try 'apt-get install curl'" $CURL
command_exists "You do not seem to have jq installed - try 'brew install jq' or 'apt-get install jq'" jq

cfssl version >/dev/null 2>/dev/null || install_cfssl

KUBE_USER=${KUBE_USER:-"$1"}
if [ -z "$KUBE_USER" ]; then
  read -r -p "What is your username? (example: a.user)> " KUBE_USER
fi

if [ -z "$KUBE_USER" ]; then
  echo "Invalid user"
  exit 1
fi

ESCAPED_USER=$(echo $KUBE_USER | tr -cd "[a-z]")

echo "Hello $ESCAPED_USER"

if [ ! -x "${BIN_DIR}/kubectl" ]; then
  echo "Installing kubectl (you will need to allow admin access)..."
  $SUDO $CURL -o ${BIN_DIR}/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${DISTRO}/${ARCH}/kubectl
  $SUDO chmod a+x ${BIN_DIR}/kubectl
fi

if [ ! -d "${DIR}" ]; then
  echo "Initalizing kube configuration"

  mkdir -p "${DIR}"

  if [ -f "${DIR}/config" ]; then
    cp "${DIR}/config" "${DIR}/config.$$"
  fi

  $CURL -o "${DIR}/ca.pem" https://raw.githubusercontent.com/fiksn/kubestart/master/ca.pem 2>/dev/null

  cat <<EOF > "${DIR}/config"
apiVersion: v1
clusters:
- cluster:
    certificate-authority: ./ca.pem
    server: https://10.27.26.98:443
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
fi

cat <<EOF | cfssl genkey - | cfssljson -bare $ESCAPED_USER
{
  "CN": "$ESCAPED_USER",
  "key": {
    "algo": "ecdsa",
    "size": 256
  }
}
EOF

echo "Creating certficate request..."
cat <<EOF | $CURL --cacert "${DIR}/ca.pem" -X POST --data-binary @/dev/stdin  -H "Content-Type: application/yaml" -H "Accept: application/json" ${KUBE_MASTER}/apis/certificates.k8s.io/v1beta1/certificatesigningrequests 2>/dev/null
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: $ESCAPED_USER
spec:
  groups:
  - system:authenticated
  request: $(cat $ESCAPED_USER.csr | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

mv -f ${ESCAPED_USER}-key.pem "${DIR}/${ESCAPED_USER}.key"

$CURL -o "$DIR/cert.sh" https://raw.githubusercontent.com/fiksn/kubestart/master/cert.sh 2>/dev/null
chmod a+x "$DIR/cert.sh"

echo "Somebody with the privilege now needs to do \"kubectl certificate approve ${ESCAPED_USER}\" and give you the correct role through RBAC"
echo "Then you need to run $DIR/cert.sh to obtain the signed certificate"
