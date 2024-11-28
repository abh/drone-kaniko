#!/busybox/sh

set -euo pipefail

DRONE_KANIKO_VERSION=0-dev

echo "Drone Kaniko Plugin ${DRONE_KANIKO_VERSION}"

export PATH=$PATH:/kaniko/

REGISTRY=${PLUGIN_REGISTRY:-index.docker.io}
PLUGIN_DOCKER_CONFIG=${PLUGIN_DOCKER_CONFIG:-}

DOCKER_CONFIG_PATH=/kaniko/.docker/config.json

if [ "${PLUGIN_USERNAME:-}" ] || [ "${PLUGIN_PASSWORD:-}" ]; then
    DOCKER_AUTH=`echo -n "${PLUGIN_USERNAME}:${PLUGIN_PASSWORD}" | base64 | tr -d "\n"`

    cat > ${DOCKER_CONFIG_PATH} <<DOCKERJSON
{
    "auths": {
        "${REGISTRY}": {
            "auth": "${DOCKER_AUTH}"
        }
    }
}
DOCKERJSON
fi

if [ -n "${PLUGIN_DOCKER_CONFIG}" ]; then
    (echo ${PLUGIN_DOCKER_CONFIG}; echo
     if [ -f "${DOCKER_CONFIG_PATH}" ]; then
         cat ${DOCKER_CONFIG_PATH}
     fi
    ) | /kaniko/jq -s '.[0] * .[1]' > ${DOCKER_CONFIG_PATH}.tmp && mv ${DOCKER_CONFIG_PATH}.tmp ${DOCKER_CONFIG_PATH}
fi

if [ "${PLUGIN_JSON_KEY:-}" ];then
    echo "${PLUGIN_JSON_KEY}" > /kaniko/gcr.json
    export GOOGLE_APPLICATION_CREDENTIALS=/kaniko/gcr.json
fi

DOCKERFILE=${PLUGIN_DOCKERFILE:-Dockerfile}
CONTEXT=${PLUGIN_CONTEXT:-$PWD}
LOG=${PLUGIN_LOG:-info}
EXTRA_OPTS=""

if [[ -n "${PLUGIN_TARGET:-}" ]]; then
    TARGET="--target=${PLUGIN_TARGET}"
fi

if [[ "${PLUGIN_SKIP_TLS_VERIFY:-}" == "true" ]]; then
    EXTRA_OPTS="--skip-tls-verify=true"
fi

if [[ "${PLUGIN_CACHE:-}" == "true" ]]; then
    CACHE="--cache=true"
fi

if [ -n "${PLUGIN_CACHE_REPO:-}" ]; then
    CACHE_REPO="--cache-repo=${REGISTRY}/${PLUGIN_CACHE_REPO}"
fi

if [ -n "${PLUGIN_CACHE_TTL:-}" ]; then
    CACHE_TTL="--cache-ttl=${PLUGIN_CACHE_TTL}"
fi

if [ -n "${PLUGIN_BUILD_ARGS:-}" ]; then
    BUILD_ARGS=$(echo "${PLUGIN_BUILD_ARGS}" | tr ',' '\n' | while read build_arg; do echo "--build-arg=${build_arg}"; done)
fi

if [ -n "${PLUGIN_BUILD_ARGS_FROM_ENV:-}" ]; then
    BUILD_ARGS_FROM_ENV=$(echo "${PLUGIN_BUILD_ARGS_FROM_ENV}" | tr ',' '\n' | while read build_arg; do echo "--build-arg ${build_arg}=$(eval "echo \$$build_arg")"; done)
fi

# auto_tag, if set auto_tag: true, auto generate .tags file
# support format Major.Minor.Release or start with `v`
# docker tags: Major, Major.Minor, Major.Minor.Release and latest
if [[ "${PLUGIN_AUTO_TAG:-}" == "true" ]]; then
    TAG=$(echo "${DRONE_TAG:-}" |sed 's/^v//g')
    part=$(echo "${TAG}" |tr '.' '\n' |wc -l)
    # expect number
    echo ${TAG} |grep -E "[a-z-]" &>/dev/null && isNum=1 || isNum=0

    if [ ! -n "${TAG:-}" ];then
        echo "latest" > .tags
    elif [ ${isNum} -eq 1 -o ${part} -gt 3 ];then
        echo "${TAG},latest" > .tags
    else
        major=$(echo "${TAG}" |awk -F'.' '{print $1}')
        minor=$(echo "${TAG}" |awk -F'.' '{print $2}')
        release=$(echo "${TAG}" |awk -F'.' '{print $3}')

        major=${major:-0}
        minor=${minor:-0}
        release=${release:-0}

        echo -n "${major},${major}.${minor},${major}.${minor}.${release},latest," > .tags
        echo    "v${major},v${major}.${minor},v${major}.${minor}.${release}" >> .tags
    fi
fi

if [ -n "${PLUGIN_TAGS:-}" ]; then
    if [ -f .tags ]; then
        echo $(head -1 .tags),${PLUGIN_TAGS} > .tags.tmp
        mv .tags.tmp .tags
    else
        echo "No auto tags generated, just using tags from config"
        echo ${PLUGIN_TAGS} > .tags
    fi
fi

if [ -f .tags ]; then
    DESTINATIONS=$(cat .tags| tr ',' '\n' | \
        while read tag; do
            echo "Setting up destination for $tag" >> /dev/stderr
            if [[ "${tag}" == "SHA7" ]]; then
                tag=$(echo ${DRONE_COMMIT_SHA} | cut -c1-7)
                echo "SHA7: $tag"  >> /dev/stderr
            fi
            if [[ "${tag}" == "SHAABBREV" ]]; then
                tag=$(echo ${DRONE_COMMIT_SHA} | cut -c1-8)
                echo "SHA abbreviation: $tag"  >> /dev/stderr
            fi

            echo "--destination=${REGISTRY}/${PLUGIN_REPO}:${tag} ";
        done)
elif [ -n "${PLUGIN_REPO:-}" ]; then
    DESTINATIONS="--destination=${REGISTRY}/${PLUGIN_REPO}:latest"
else
    DESTINATIONS="--no-push"
    # Cache is not valid with --no-push
    CACHE=""
fi

echo DESTINATIONS: ${DESTINATIONS} >&2

set -x

/kaniko/executor -v ${LOG} \
    --context=${CONTEXT} \
    --dockerfile=${DOCKERFILE} \
    ${EXTRA_OPTS} \
    ${DESTINATIONS} \
    ${CACHE:-} \
    ${CACHE_TTL:-} \
    ${CACHE_REPO:-} \
    ${TARGET:-} \
    ${BUILD_ARGS:-} \
    ${BUILD_ARGS_FROM_ENV:-} >&2
