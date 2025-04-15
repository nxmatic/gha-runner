#!/usr/bin/env -S bash -ex -o pipefail

env=( ADDITIONAL_FLAGS
      INTERNAL_DOMAIN
      GOPROXY
      LABELS
      NAME
      PROJECT_NAME
      REGISTER_TO
      WORKDIR
    )

set -a
source <( sudo cat /proc/1/environ | tr '\0' '\n' | grep -E "^RUNNER_($(IFS='|'; echo "${env[*]}"))=" )

KMS_URL=http://kms.gha.${RUNNER_PROJECT_NAME:-develop}.${RUNNER_INTERNAL_DOMAIN:-internal}:3000
GOPROXY=${RUNNER_GOPROXY}
set +a

cd ~runner

:register:workdir() {
  echo ${RUNNER_WORKDIR:-work}
}

:register:name() {
  echo ${RUNNER_NAME:-runner}
}

:register:to() {
  echo ${RUNNER_REGISTER_TO}
}

:register:labels() {
  echo ${RUNNER_LABELS}
}

:kms:server:path() {
  local service=$1
  local path=${RUNNER_REGISTER_TO}/$service

  if [[ "${RUNNER_REGISTER_TO}" == *\/* ]]; then
    path=repo/${path}
  fi

  echo $path
}

:kms:register:token() {
  curl -s ${KMS_URL}/$( :kms:server:path registration-token)
}

:kms:remove:token() {
  curl -s ${KMS_URL}/$( :kms:server:path remove-token)
}

register() {
    bash -x ./config.sh \
      --name $( :register:name ) \
      --work $( :register:workdir ) \
      --unattended \
      --disableupdate \
      --url "https://github.com/$( :register:to )" \
      --token $( :kms:register:token ) \
      --labels "$( :register:labels )" \
      ${RUNNER_ADDITIONAL_FLAGS} 
}

remove() {
  bash -x ./config.sh remove --token "$( :kms:remove:token )"
}

register

trap 'remove' EXIT

trap 'exit 130' INT
trap 'exit 143' TERM

./runsvc.sh "$*" &

wait $!
