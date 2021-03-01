#!/bin/bash

retype_version="1.0.0"

use_dotnet=false
_ifs="${IFS}"

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

Aborting documentation build process."
  fi
else
  echo -n "Installing retype v${retype_version} using "
  if ${use_dotnet}; then
    echo -n "dotnet tool: "

    result="$(dotnet tool install --global --version ${retype_version} retypeapp 2>&1)"
    retstat="${?}"

    if [ ${retstat} -ne 0 ]; then
      echo "failed."
      fail "unable to install retype using the dotnet tool.
Output for the 'dotnet tool' command:
----
${result}
----

Aborting documentation build process."
    fi
else
    echo -n "NPM package manager: "

    result="$(npm install --global retypeapp@${retype_version} 2>&1)"
    retstat="${?}"

    if [ ${retstat} -ne 0 ]; then
      fail_nl "unable to install retype using the NPM package manager.
Output for the NPM install command:
----
${result}
----

Aborting documentation build process."
    fi
  fi
  echo "done."
fi

echo -n "Determining temporary target folder to place parsed documentation: "
# by letting it create the directory we can guarantee no other call of mktemp could reference
# the same path.
destdir="$(mktemp -d)"
echo "${destdir}"

echo -n "Creating configuration file: "

# FIXME: 'base' below will make it work in generic github.io hosting but would break for
# FIXME: INPUT_PROJECT_NAME is empty albeit being provided.
cat << EOF > "${destdir}/retype.json"
{
  "input": "$(pwd)/${docsroot#./}",
  "output": "${destdir}/output",
  "base": "${GITHUB_REPOSITORY##*/}",
  "identity": {
    "title": "${INPUT_PROJECT_NAME}",
    "label": "${INPUT_PROJECT_NAME}"
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
result="$(time retype build --verbose 2>&1)"
retstat="${?}"
cd - > /dev/null 2>&1

if [ ${retstat} -ne 0 ]; then
  echo "error."
  fail "retype build command failed with exit code ${retstat}. Command output:
--------
${result}
--------

Aborting documentation build process."
else
  echo "done.
Documentation static website built at: ${destdir}/output:"
fi

echo -n "Fetching remote to check whether gh-pages exists: "
result="$(git fetch 2>&1)"
retstat="${?}"

if [ ${retstat} -ne 0 ]; then
  fail_nl "unable to fetch remote repository for existing branchs.
Failing command output:

\$ git fetch
${result}
------------

Aborting documentation build process."
fi

needpr=false
if git branch --list --remotes --format="%(refname)" | egrep -q "^refs/remotes/origin/gh-pages\$"; then
  echo "Branch gh-pages already exists.
Branching off it: "
  needpr=true
  git checkout gh-pages > /dev/null || fail_nl "unable to checkout the gh-pages branch."
  branchname="gh-pages-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}"

  uniquer=0
  while git branch --list --remotes --format="%(refname)" | egrep -q "^refs/remotes/origin/${branchname}\$"; do
    branchname="gh-pages-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}_${uniquer}"
    uniquer=$(( 10#${uniquer} + 1 ))
    if [ ${uniquer} -gt 100 ]; then
      fail_nl "unable to get a non-existing branch name based on 'gh-pages-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}'."
    fi
  done

  echo -n "${branchname}, "
  git checkout -b "${branchname}" > /dev/null || fail_nl "unable to switch to new branch '${branchname}'."
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
  echo -n "Creating new, orphan, gh-pages branch: "
  git checkout --orphan gh-pages || fail_nl "unable to checkout to a new, orphan branch called 'gh-pages'."

  echo -n "cleanup"
  git reset HEAD -- . || fail_nl "unable to remove original files from staging."

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
cp -dpR "${destdir}/output/." . || fail_nl "unable to copy built website files."
echo "done."

echo -n "Committing files: "
git add . > /dev/null || fail_nl "unable to stage website files."

git config user.email hello@object.net
git config user.name "Retype documentation builder v$(retype --version | strings)"
result="$(git commit -m "Adds documentation files to the repository.

Process triggered by ${GITHUB_ACTOR}.")" || {
  fail_nl "unable to commit files. Command output:
git commit...
-----
${result}
-----

Aborting documentation build process."
}

# TODO: honor input no-push-back
result="$(git push origin HEAD)"
retstat="${?}"
if [ ${retstat} -ne 0 ]; then
  fail_nl "unable to push changes back"
fi

if ${needpr}; then
  # TODO: https://docs.github.com/en/rest/reference/pulls#create-a-pull-request
  # Auth with: https://docs.github.com/en/actions/reference/authentication-in-a-workflow#about-the-github_token-secret
  echo "Pull request creation not supported at this time. The branch is pushed but merging should be done by the user."
fi

echo "Process completed successfully."