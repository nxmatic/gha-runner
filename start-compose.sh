#!/usr/bin/env -S bash -e -o pipefail

shopt -s globstar

CWD="$(dirname $(realpath "$0"))"

[[ -r ${ENVRC:=${CWD}/.start.env} ]] &&
  source ${ENVRC}

# Computing repository URL assuming releases x.y.z are on packages.nuxeo.com, others are on ghcr.io

GITHUB_REPOSIYORY=${GITHUB_REPOSITORY:-$(
  if command -v gh >/dev/null 2>&1 &&
     command -v jq >/dev/null 2>&1; then
    gh repo view --json nameWithOwner | jq -r .nameWithOwner
  else
    echo nuxeo/nos
  fi
)}
GITHUB_WORKDPACE=${GITHUB_WORKSPACE:-$( git rev-parse --show-toplevel )}
GIT_WORKTREE=${GIT_WORKTREE:-$( git rev-parse --show-toplevel )}

BASE_URL=${DOWNSTREAM:-$( [[ ${IMAGE_VERSION} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] &&
			  echo "docker-nos-private.packages.nuxeo.com" ||
			  echo "ghcr.io/${GITHUB_REPOSITORY}" )}
IMAGE_VERSION=${VERSION:-"0.0.0-dev"}

COMPOSE_PRJ=${PROJECT_NAME:-"develop"}
COMPOSE_BUILD=${COMPOSE_BUILD:-"false"}
COMPOSE_PROFILES=${COMPOSE_PROFILES:-""} # inherits from environment if defined

declare -A LOCAL_NETWORK_BY_PROJECT=(
  ["develop"]="16"
  ["ftest"]="17"
)

OPTS_BASE_URL="l"
OPTS_COMPOSE_BUILD="b"
OPTS_IMAGE_TYPE="t"
OPTS_IMAGE_VERSION="v"
OPTS_COMPOSE_PRJ="p"
OPTS_CONF_NAME="c"
OPTS_SUSPEND="s"

usage() {
  [[ $# -ne 0 ]] &&
    echo "$*" >&2
  echo "" 1>&2
  cat <<! >&2

Start Docker Compose locally

  Usage: ${0} [-${OPTS_COMPOSE_PRJ} <project_name>] [-${OPTS_COMPOSE_UP} <service_name>]  [-${OPTS_CONF_NAME} <con_name>]  [-${OPTS_IMAGE_TYPE} <image_type>]  [-${OPTS_IMAGE_VERSION} <image_version>] [-${OPTS_SUSPEND} <suspend_value>] [-${OPTS_COMPOSE_EXEC} <command>]

  Options:
    -${OPTS_IMAGE_TYPE} <image_type>                   Docker image type to use: preview|full|gitty|portal. Default: "${IMAGE_TYPE}".
    -${OPTS_IMAGE_VERSION} <image_version>             Docker image version to use: x.x.x-?. Default: "${IMAGE_VERSION}".
    -${OPTS_COMPOSE_PRJ} <project_name>                Docker-Compose project name. Default: "${COMPOSE_PRJ}".
    -${OPTS_COMPOSE_BUILD} [true|false]                Build container images. Default: "${COMPOSE_BUILD}".
    -${OPTS_CONF_NAME} <conf name>                     Nuxeo properties configuration name <conf_name>-props.conf file. Default: "${CONF_NAME}".
    -${OPTS_SUSPEND} <suspend_value>                   Java debug suspend value: y|n. Default: "${SUSPEND}".
    -${OPTS_BASE_URL} <name>                           Docker registry to fetch. Default: (ghcr.io|packages.nuxeo.com).
!
  exit 1
}

while getopts ":h${OPTS_IMAGE_TYPE}:${OPTS_IMAGE_VERSION}:${OPTS_BASE_URL}:${OPTS_COMPOSE_PRJ}:${OPTS_SUSPEND}:${OPTS_COMPOSE_SERVICES}:${OPTS_CONF_NAME}:${OPTS_COMPOSE_BUILD}:${OPTS_COMPOSE_EXEC}:-" o; do
  case "${o}" in
  l)
    BASE_URL="${OPTARG}"
    ;;
  c)
    CONF_NAME="${OPTARG}"
    ;;
  b)
    COMPOSE_BUILD="${OPTARG}"
   ;;
  p)
   C OMPOSE_PRJ="${OPTARG}"
    ;;
  t)
    IMAGE_TYPE="${OPTARG}"
    ;;
  s)
    SUSPEND="${OPTARG}"
    ;;
  u)
    COMPOSE_SERVICES+=( "${OPTARG}" )
    ;;
  e)
    COMPOSE_COMMAND="${OPTARG}"
    ;;
  v)
    IMAGE_VERSION="${OPTARG}"
    ;;
  ?)
    usage "wrong option ${OPTARG}"
    ;;
  esac
done

shift $((OPTIND - 1))

COMPOSE_COMMAND_LINE=( "${@}" )


# Computing repository URL assuming releases x.y.z are on packages.nuxeo.com, others are on ghcr.io

# Computing compose options
COMPOSE_OPTIONS=( --project-name="${COMPOSE_PRJ}" )

for profile in $COMPOSE_PROFILES; do 
  COMPOSE_OPTIONS+=( "--profile=$profile"  ) # add profile
done

pushd ${CWD} >/dev/null
COMPOSE_OPTIONS+=( "--file=${CWD}/docker-compose.yml" )

for overlay in **/docker-compose*~overlay.yml; do
  [[ -r $overlay ]] &&
    COMPOSE_OPTIONS+=( "--file=${CWD}/$overlay" ) # add overlay
done

COMPOSE_OPTIONS+=( "--env-file=${CWD}/.start.env" ) # add starting env file

cat <<! > .start.env
COMPOSE_PROFILES="${COMPOSE_PROFILES}"
COMPOSE_BUILD="${COMPOSE_BUILD}"

PROJECT_NAME="${COMPOSE_PRJ}"

VERSION="${IMAGE_VERSION}"
DOWNSTREAM="${BASE_URL}"

INTERNAL_DNS_DOMAIN="${COMPOSE_PRJ}.internal"

LOCAL_DNS_DOMAIN="${COMPOSE_PRJ}.local"
LOCAL_NETWORK=${LOCAL_NETWORK_BY_PROJECT[${COMPOSE_PRJ}]}

GITHUB_WORKSPACE="${GITHUB_WORKSPACE}"
GIT_WORKTREE="${GIT_WORKTREE}"

RUNNER_OWNER="${RUNNER_OWNER:=${GITHUB_OWNER:=nuxeo}}"
!

popd >/dev/null

# Parse options without specifying them
OPTIND=1
while getopts ":*" opt "${COMPOSE_COMMAND_LINE[@]:1}"; do
  case $opt in
    \?) ;;
  esac
done

COMPOSE_COMMAND="${COMPOSE_COMMAND_LINE[0]}"
COMPOSE_COMMAND_OPTIONS=( "${COMPOSE_COMMAND_LINE[@]:1:$((OPTIND-1))}" )
COMPOSE_COMMAND_ARGS=( "${COMPOSE_COMMAND_LINE[@]:$((OPTIND))}" )

case "${COMPOSE_COMMAND}" in
  "up")
    COMPOSE_COMMAND_OPTIONS+=( --detach --pull=always --remove-orphans )
    [[ "${COMPOSE_BUILD:-true}" == "true" ]] &&
      COMPOSE_COMMAND_OPTIONS+=(--build)
    ;;
esac

docker compose \
       "${COMPOSE_OPTIONS[@]}" \
       "${COMPOSE_COMMAND}" \
       "${COMPOSE_COMMAND_OPTIONS[@]}" \
       "${COMPOSE_COMMAND_ARGS[@]}"
