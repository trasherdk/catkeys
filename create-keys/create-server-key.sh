#! /usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cleanup () {
  rm -f \
    "$KEYDIR/ca-crt.pem" \
    "$KEYDIR/ca-key.pem" \
    "$KEYDIR/crt.pem" \
    "$KEYDIR/key.pem" \
    "$KEYDIR/csr.pem" \
    "$KEYDIR/.srl"
}

trap cleanup SIGHUP SIGINT EXIT

while getopts ":n:k:" o; do
  case "${o}" in
    n)
      COMMON_NAME="${OPTARG}"
      ;;
    k)
      KEYDIR="${OPTARG}"
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "$COMMON_NAME" ]; then
  COMMON_NAME=localhost
fi

mkdir -p "$KEYDIR"

openssl \
  req \
  -new \
  -x509 \
  -days 9999 \
  -config "$DIR/cnf/ca.cnf" \
  -keyout "$KEYDIR/ca-key.pem" \
  -out "$KEYDIR/ca-crt.pem" \
  -nodes \
  2> /dev/null

openssl genrsa -out "$KEYDIR/key.pem" 4096 2> /dev/null

SUBJECT_LOCATION="C=GB/ST=Tyne and Wear/L=Newcastle upon Tyne"
SUBJECT_ORG="O=clientAuthenticatedHttps/OU=clientAuthenticatedHttps"

openssl \
  req \
  -new \
  -subj "/$SUBJECT_LOCATION/$SUBJECT_ORG/CN=$COMMON_NAME" \
  -key "$KEYDIR/key.pem" \
  -out "$KEYDIR/csr.pem" \
  2> /dev/null

openssl \
  x509 \
  -req \
  -days \
  9999 \
  -in "$KEYDIR/csr.pem" \
  -CA "$KEYDIR/ca-crt.pem" \
  -CAkey "$KEYDIR/ca-key.pem" \
  -CAcreateserial \
  -CAserial "$KEYDIR/.srl" \
  -out "$KEYDIR/crt.pem" \
  2> /dev/null

tar -czf "$KEYDIR/server.cahkey" \
  -C "$KEYDIR" \
  "ca-crt.pem" "ca-key.pem" "crt.pem" "key.pem" ".srl"

rm -f \
  "$KEYDIR/ca-crt.pem" \
  "$KEYDIR/ca-key.pem" \
  "$KEYDIR/crt.pem" \
  "$KEYDIR/key.pem" \
  "$KEYDIR/csr.pem" \
  "$KEYDIR/.srl"
