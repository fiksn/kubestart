#!/bin/sh

export CURL=${CURL:-"curl --connect-timeout 5 --max-time 30"}
export KUBE_MASTER=${KUBE_MASTER:-"https://10.27.26.98:443"}
export DIR=${DIR:-"$HOME/.kube"}

command_exists () {
  MSG=$1
  shift 1
  "$@" > /dev/null 2>/dev/null
  if [ $? -eq 127 ]; then
    echo "$MSG"
    exit 1
  fi
}

command_exists "You do not seem to have curl installed" $CURL
command_exists "You do not seem to have jq installed - try 'brew install jq' or 'apt-get install jq'" jq

finish () {
  rm -f tempcert*
}
trap finish EXIT

ESCAPED_USER=${ESCAPED_USER:-$(cat ${DIR}/config | grep client-certificate | cut -d":" -f 2 | sed 's/.crt//g' | tr -d "/. ")}
if [ -z "$ESCAPED_USER" ]; then
  echo "Is $DIR/config correct? You might also want to set ESCAPED_USER=auser" 
  exit 1
fi

DEST="${DIR}/${ESCAPED_USER}.crt"

if [ -s "$DEST" ]; then
  if [ -z "$FORCE" ]; then
    echo "File $DEST already exists, you might want to set FORCE=true"
    exit 1
  fi
fi

while true; do
  echo "$ESCAPED_USER trying to fetch certificate"

  OUT="$(mktemp tempcertXXXXXXX)"
  $CURL --cacert "${DIR}/ca.pem" -H "Accept: application/json" ${KUBE_MASTER}/apis/certificates.k8s.io/v1beta1/certificatesigningrequests/${ESCAPED_USER} 2>/dev/null | jq .status.certificate | tr -d '"' | base64 --decode > $OUT

  if [ -s "$OUT" ]; then
    echo "Certificate obtained"
    break
  else
    echo "There was a problem with certification obtaining"
    rm -f $OUT
  fi
  
  echo "Sleeping..."
  sleep 10
done

if [ ! -s "$DEST" ] || [ -n "$FORCE" ]; then
  echo "Moved certificate in-place..."
  mv -f $OUT $DEST
fi
