#!/bin/bash

retype_version="1.0.0"

use_dotnet=false
_ifs="${IFS}"
abortbuildmsg="Aborting documentation build process."

if [ "${OSTYPE}" == "msys" ]; then
  MSYS_TMPDIR="$(mount | egrep "^[^ ]+ on /tmp type" | cut -f1 -d" ")"

  if [ -z "${MSYS_TMPDIR}" ]; then
    fail "unable to query MSYS mounted /tmp/ directory. Current mtab:
$(mount)
----

${abortbuildmsg}"
  fi

  # MSYS's git will insist in turning LF files into CRLF.
  # We don't need to touch them.
  git config core.autocrlf false
  git config core.eol native
  git reset --quiet --hard HEAD -- .
  git checkout --quiet -- .

  function cf_path() {
    local linuxpath="${@}"
    local drivepath

    if [ "${linuxpath::1}" != "/" ]; then
      #relative path
      echo "${linuxpath}"
      return 0
    else
      drivepath="${linuxpath::3}"
      if [ -z "${drivepath/\/[a-zA-Z]\/}" ]; then
        echo "${drivepath:1:1}:${linuxpath#/?}"
        return 0
      elif [ "${linuxpath::5}" == "/tmp/" ]; then
        echo "${MSYS_TMPDIR}/${linuxpath#/*/}"
      else
        # could be a network drive, something we don't support or suppose will ever
        # be used as absolute path under windows.
        return 1
      fi
    fi
  }
else
  function cf_path() {
    echo "${@}"
    return 0
  }
fi

function fail() {
  local msg="${@}"

  >&2 echo "*** Error: ${msg}"
  exit 1
}

function fail_nl() {
  local msg="${@}"

  echo "error."
  fail "${msg}"
}

function fail_cmd() {
  local nl="${1}" msg="${2}" cmd="${3}" output="${4}"
  local multiline_msg

  multiline_msg="${msg}.
Failed command and output:

\$ ${cmd}

${output}
----

${abortbuildmsg}"

  if [ "${nl}" == true ]; then
    fail_nl "${multiline_msg}"
  else
    fail "${multiline_msg}"
  fi
}

# We prefer dotnet if available as the package size is (much) smaller.
if which dotnet > /dev/null 2>&1 && [ "$(dotnet --version | cut -f1 -d.)" == "5" ]; then
  use_dotnet=true
elif ! which node > /dev/null 2>&1 || [ "$(node --version | cut -f1 -d. | cut -b2-)" -lt 14 ]; then
  fail "Can't find suitable dotnet or node installation to install retype package with."
fi

echo -n "Determining root for documentation in repository: "

if [ ! -z "${INPUT_INPUT_ROOT}" ]; then
  docsroot="${INPUT_INPUT_ROOT}"

  # remove any heading slashes to the root path
  while [ "${docsroot::1}" == "/" ]; do
    docsroot="${docsroot:1}"
  done

  if [ -z "${docroot}" ]; then
    fail_nl "Invalid documentation root directory: ${INPUT_INPUT_ROOT}"
  fi

  if [ ! -d "${docroot}" ]; then
    fail_nl "Input documentation root directory not found: ${docroot}"
  fi
else
  IFS=$'\n'
  markdown_files=($(find ./ -type f -name "*.md"))
  IFS="${_ifs}"

  if [ ${#markdown_files[@]} -eq 0 ]; then
    fail_nl "Unable to locate markdown documentation files."
  elif [ ${#markdown_files[@]} -eq 1 ]; then
    docsroot="${markdown_files[0]}"
    docsroot="${docsroot%/*}"
  else
    depth=1
    while [ ${depth} -lt 100 ]; do
      if [ $(IFS=$'\n'; echo "${markdown_files[*]}" | cut -f1-${depth} -d/ | sort -u | wc -l) -ne 1 ]; then
        docsroot="$(echo "${markdown_files[0]}" | cut -f1-$(( 10#${depth} - 1 )) -d/)"
        break
      fi
      depth=$(( 10#${depth} + 1 ))
    done

    # point to root if failed
    if [ -z "${docsroot}" ]; then
      docsroot="."
    fi
  fi
fi

echo "${docsroot}/"

retype_path="$(which retype 2> /dev/null)"
retstat="${?}"

if [ ${retstat} -eq 0 ]; then
  if [ "$(retype --version | strings)" == "${retype_version}" ]; then
    echo "Using existing retype installation at: ${retype_path}"
  else
    fail "Found existing installation of retype for a different version than this action is intended to work with.
Expected version: ${retype_version}
Available version: $(retype --version | strings)

${abortbuildmsg}"
  fi
else
  echo -n "Installing Retype v${retype_version} using "
  if ${use_dotnet}; then
    echo -n "dotnet tool: "

    cmdln=(dotnet tool install --global --version ${retype_version} retypeapp)
    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "unable to install retype using the dotnet tool" "${cmdln[@]}" "${result}"
else
    echo -n "NPM package manager: "

    cmdln=(npm install --global "retypeapp@${retype_version}")
    result="$("${cmdln[@]}" 2>&1)" || \
      fail_cmd true "unable to install retype using the NPM package manager" "${cmdln[@]}" "${result}"
  fi
  echo "done."
fi

echo -n "Determining temporary target folder to place parsed documentation: "
# by letting it create the directory we can guarantee no other call of mktemp could reference
# the same path.
destdir="$(mktemp -d)"
echo "${destdir}"

echo -n "Creating configuration file: "

# cf_path ensures path is converted in case we are running from windows
config_input="$(cf_path "$(pwd)/${docsroot#./}")" || fail_nl "unable to parse input path: $(pwd)/${docsroot#./}"
config_output="$(cf_path "${destdir}/output")" || fail_nl "unable to parse output path: ${destdir}/output"

# FIXME: 'base' below will make it work in generic github.io hosting but would break for
# FIXME: INPUT_PROJECT_NAME is empty albeit being provided.
cat << EOF > "${destdir}/retype.json"
{
  "input": "${config_input}",
  "output": "${config_output}",
  "base": "${GITHUB_REPOSITORY##*/}",
  "identity": {
    "title": "${INPUT_PROJECT_NAME}"
  },
  "links": [{
    "text": "Project Repository",
    "link": "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
  }],
  "nav": [{
    "path": "/",
    "icon": "home"
  }],
  "footer": {
    "copyright": "Copyright &copy; {{ year }}. All rights reserved."
  }
}
EOF
echo "done."

echo -n "Building documentation: "
cd "${destdir}"
result="$(retype build --verbose 2>&1)" || \
  fail_cmd true "retype build command failed with exit code ${retstat}" "retype build --verbose" "${result}"

cd - > /dev/null 2>&1

echo -n "done.
Documentation static website built at: ${destdir}/output"
if [ "${config_output}" != "${destdir}/output" ]; then
  echo -n " (${config_output})"
fi
echo ""

basebranch="${INPUT_BRANCH-gh-pages}"
branchname="${basebranch}"
echo -n "Target branch to publish to: ${branchname}"

echo -n "Fetching remote for existing branches: "
result="$(git fetch 2>&1)" || \
  fail_cmd true "unable to fetch remote repository for existing branches" "git fetch" "${result}"
echo "done."

needpr=false
if git branch --list --remotes --format="%(refname)" | egrep -q "^refs/remotes/origin/${branchname}\$"; then
  echo "Branch '${branchname}' already exists."

  if [ "${INPUT_OVERWRITE_BRANCH}" == "true" ]; then
    echo -n "Switching to the '${branchname}' branch: "
    overwrite_branch=true
  else
    echo -n "Creating a new branch off '${branchname}': "
    needpr=true
    overwrite_branch=false
  fi

  git checkout --quiet "${branchname}" || fail_nl "unable to checkout the '${branchname}' branch."

  if ! ${overwrite_branch}; then
    branchname="${basebranch}-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}"

    uniquer=0
    while git branch --list --remotes --format="%(refname)" | egrep -q "^refs/remotes/origin/${branchname}\$"; do
      branchname="${basebranch}-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}_${uniquer}"
      uniquer=$(( 10#${uniquer} + 1 ))
      if [ ${uniquer} -gt 100 ]; then
        fail_nl "unable to get a non-existing branch name based on '${basebranch}-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}'."
      fi
    done

    echo -n "${branchname}, "
    git checkout --quiet -b "${branchname}" || fail_nl "unable to switch to new branch '${branchname}'."
  fi
  echo "done."

  echo -n "Cleaning up branch: "

  keepcname=false
  if [ -e CNAME ]; then
    keepcname=true
  fi

  git rm -r --quiet . || fail_nl "unable to git-rm checked out repository."

  if ${keepcname}; then
    git checkout -- CNAME || fail_nl "unable to check out CNAME file after git-rm."
    git reset HEAD -- CNAME || fail_nl "unable to reset CNAME file to previous branch HEAD."
  fi

  IFS=$'\n'
  rootdirs=($(git ls-files --other | cut -f1 -d/ | sort -u))
  IFS="${_ifs}"

  for rootdir in "${rootdirs[@]}"; do
    git rm -r --quiet "${rootdir}" || fail_nl "unable to remove directory at root: ${rootdir}"
  done

  echo "done."
else
  echo -n "Creating new, orphan, '${branchname}' branch: "
  git checkout --quiet --orphan "${branchname}" || fail_nl "unable to checkout to a new, orphan branch called '${branchname}'."

  echo -n "cleanup"
  git reset --quiet HEAD -- . || fail_nl "unable to remove original files from staging."

  git clean -x -q -f || fail_nl "unable to clean-up repository from non-website-related files."

  IFS=$'\n'
  rootdirs=($(git ls-files --other | cut -f1 -d/ | sort -u))
  IFS="${_ifs}"

  for rootdir in "${rootdirs[@]}"; do
    git clean -x -q -f "${rootdir}" || fail_nl "unable to clean up root directory: ${rootdir}"
  done

  echo ", done."
fi

echo -n "Copying over built website files: "
cp -pPR "${destdir}/output/." . || fail_nl "unable to copy built website files."
echo "done."

echo -n "Committing files: "
git add . > /dev/null || fail_nl "unable to stage website files."

git config user.email hello@object.net
git config user.name "Retype documentation builder v$(retype --version | strings)"

cmdln=(git commit --quiet -m "Adds documentation files to the repository.

Process triggered by ${GITHUB_ACTOR}.")

result="$("${cmdln[@]}" 2>&1)" || \
  fail_cmd true "unable to commit website files" "${cmdln[@]}" "${result}"
echo "done."

if [ "${INPUT_NO_PUSH_BACK}" != "true" ]; then
  echo -n "Pushing website to GitHub: "
  result="$(git push --quiet origin HEAD 2>&1)" || \
    fail_cmd true "unable to push branch to GitHub" "git push origin HEAD" "${result}"
  echo "done."

  if ${needpr}; then
    # TODO: https://docs.github.com/en/rest/reference/pulls#create-a-pull-request
    # Auth with: https://docs.github.com/en/actions/reference/authentication-in-a-workflow#about-the-github_token-secret
    echo "Pull request creation not supported at this time. The branch is pushed but merging should be done by the user."
  fi
else
  echo "no-push-back: skipping GitHub interactions (push, pull request)."
fi

echo "Retype documentation build completed successfully."