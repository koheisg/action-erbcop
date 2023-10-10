#!/bin/sh -e
version() {
  if [ -n "$1" ]; then
    echo "-v $1"
  fi
}

cd "${GITHUB_WORKSPACE}/${INPUT_WORKDIR}" || exit
export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"

TEMP_PATH="$(mktemp -d)"
PATH="${TEMP_PATH}:$PATH"

echo '::group::🐶 Installing reviewdog ... https://github.com/reviewdog/reviewdog'
curl -sfL https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b "${TEMP_PATH}" "${REVIEWDOG_VERSION}" 2>&1
echo '::endgroup::'

if [ "${INPUT_SKIP_INSTALL}" = "false" ]; then
  echo '::group:: Installing erbcop with extensions ... https://github.com/r7kamura/erbcop'
  # if 'gemfile' erbcop version selected
  if [ "${INPUT_ERBCOP_VERSION}" = "gemfile" ]; then
    # if Gemfile.lock is here
    if [ -f 'Gemfile.lock' ]; then
      # grep for erbcop version
      ERBCOP_GEMFILE_VERSION=$(ruby -ne 'print $& if /^\s{4}erbcop\s\(\K.*(?=\))/' Gemfile.lock)

      # if erbcop version found, then pass it to the gem install
      # left it empty otherwise, so no version will be passed
      if [ -n "$ERBCOP_GEMFILE_VERSION" ]; then
        ERBCOP_VERSION=$ERBCOP_GEMFILE_VERSION
      else
        printf "Cannot get the erbcop's version from Gemfile.lock. The latest version will be installed."
      fi
    else
      printf 'Gemfile.lock not found. The latest version will be installed.'
    fi
  else
    # set desired erbcop version
    ERBCOP_VERSION=$INPUT_ERBCOP_VERSION
  fi

  gem install -N erbcop --version "${ERBCOP_VERSION}"

  # Traverse over list of erbcop extensions
  for extension in $INPUT_ERBCOP_EXTENSIONS; do
    # grep for name and version
    INPUT_ERBCOP_EXTENSION_NAME=$(echo "$extension" |awk 'BEGIN { FS = ":" } ; { print $1 }')
    INPUT_ERBCOP_EXTENSION_VERSION=$(echo "$extension" |awk 'BEGIN { FS = ":" } ; { print $2 }')

    # if version is 'gemfile'
    if [ "${INPUT_ERBCOP_EXTENSION_VERSION}" = "gemfile" ]; then
      # if Gemfile.lock is here
      if [ -f 'Gemfile.lock' ]; then
        # grep for erbcop extension version
        ERBCOP_EXTENSION_GEMFILE_VERSION=$(ruby -ne "print $& if /^\s{4}$INPUT_ERBCOP_EXTENSION_NAME\s\(\K.*(?=\))/" Gemfile.lock)

        # if erbcop extension version found, then pass it to the gem install
        # left it empty otherwise, so no version will be passed
        if [ -n "$ERBCOP_EXTENSION_GEMFILE_VERSION" ]; then
          ERBCOP_EXTENSION_VERSION=$ERBCOP_EXTENSION_GEMFILE_VERSION
        else
          printf "Cannot get the erbcop extension version from Gemfile.lock. The latest version will be installed."
        fi
      else
        printf 'Gemfile.lock not found. The latest version will be installed.'
      fi
    else
      # set desired erbcop extension version
      ERBCOP_EXTENSION_VERSION=$INPUT_ERBCOP_EXTENSION_VERSION
    fi

    # Handle extensions with no version qualifier
    if [ -z "${ERBCOP_EXTENSION_VERSION}" ]; then
      unset ERBCOP_EXTENSION_VERSION_FLAG
    else
      ERBCOP_EXTENSION_VERSION_FLAG="--version ${ERBCOP_EXTENSION_VERSION}"
    fi

    # shellcheck disable=SC2086
    gem install -N "${INPUT_ERBCOP_EXTENSION_NAME}" ${ERBCOP_EXTENSION_VERSION_FLAG}
  done
  echo '::endgroup::'
fi

export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"

if [ "${INPUT_USE_BUNDLER}" = "false" ]; then
  BUNDLE_EXEC=""
else
  BUNDLE_EXEC="bundle exec "
fi

echo '::group:: Running erbcop with reviewdog 🐶 ...'
# shellcheck disable=SC2086
${BUNDLE_EXEC}erbcop ${INPUT_ERBCOP_FLAGS} --require ${GITHUB_ACTION_PATH}/rdjson_formatter/rdjson_formatter.rb --format RdjsonFormatter \
  | reviewdog -f=rdjson \
      -name="${INPUT_TOOL_NAME}" \
      -reporter="${INPUT_REPORTER}" \
      -filter-mode="${INPUT_FILTER_MODE}" \
      -fail-on-error="${INPUT_FAIL_ON_ERROR}" \
      -level="${INPUT_LEVEL}" \
      ${INPUT_REVIEWDOG_FLAGS}

reviewdog_rc=$?
echo '::endgroup::'
exit $reviewdog_rc
