#!/bin/bash

set -o errexit
shopt -s extglob

user=${TEST_USER:?Missing TEST_USER env var}
pass=${TEST_PASS:?Missing TEST_PASS env var}
base=${TEST_URL:?Missing TEST_URL env var (base url without /pulp/api/v3)}
base=${base%%*(/)}
api=$base/pulp/api/v3
usage="usage: $0 repo dist package1.rpm [package2.rpm ... packageN.rpm]"
distro_base_path=${1?:$usage}
shift
distro_name=${1?:$usage}
shift
: ${1?:$usage}
# all args are package files
packages=("$@")

# name the repo with the base path, replacing / with _
repo_name="repo_${distro_name//"/"/_}"

[[ -n "${SUPERDEBUG:-}" ]] && { set -x; DEBUG=${DEBUG:-1}; }
function debug {
  if [[ -n "${DEBUG:-}" ]]
  then
    printf "%s\n" "$@" >&2
    return
  fi
  true
}

repo_url=$( \
  curl -Ls -G --request GET --user "$user":"$pass" \
    --url "$api/repositories/rpm/rpm/" \
    -d "name=$repo_name" \
    -d "fields=pulp_href" \
  | jq -r '.results[0].pulp_href'
)

function wait_for_task {
  local task_url=${1//"//"/\/} # double-slash breaks things :/
  local response
  local state

  echo "Polling the task until it has reached a final state."
  debug "task URL: $task_url"
  while true
  do
    response=$( curl -Ls --request GET --user "$user":"$pass" "$task_url" )
    state=$( jq -r .state <<<"$response" )
    debug "task reponse" "$(jq . <<<"$response")"
    debug "state: '$state'"
    case "$state" in
      failed|canceled)
          echo "Task in final state: ${state}"
          return 0
          ;;
      completed)
          echo "$task_url complete."
          break
          ;;
      *)
          echo "Still waiting..."
          sleep 1
          ;;
    esac
  done
}

########################################
# check if repo exists
if [[ $repo_url == 'null' ]]
then
  echo "creating repo"
  repo_url=$( \
    curl -Ls --request POST --user "$user":"$pass" \
      --url "$api/repositories/rpm/rpm/" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"$repo_name"'",
        "description": "Kong repo: '"$repo_name"'"
      }' \
    | jq -r '.pulp_href'
  )
fi

# if url = null, create failed
if [[ $repo_url == 'null' ]]
then
  exit 1
fi
echo "using $repo_url"

########################################
# create artifacts for the package files
# TODO: check for duplicated basenames
declare -A artifacts
for package in "${packages[@]}"
do
  if [[ ! ( -f "$package" && -r "$package" ) ]]
  then
    echo "warning: '$package' is not a readable file"
    continue
  fi
  debug "Attempting to upload '$package'"
  fsize=$( stat --format="%s" "$package" )
  read md5sum junk < <( md5sum "$package" )
  debug "Package has size=$fsize and md5sum=$md5sum"
  response=$( \
    curl -Ls --request POST --user "$user":"$pass" \
      --url "$api/artifacts/" \
      -F "md5=$md5sum" \
      -F "size=$size" \
      -F "file=@${package}"
  )
  debug "upload response" "$( jq . <<<"$response" )"
  dup_check=$( jq '.non_field_errors[] | select(. | contains("already exists"))' <<<"$response" 2>/dev/null || true )
  if [[ -n  "$dup_check" ]]
  then
    # extract checksum from exists error and get the href
    for sumtype in md5 sha1 sha224 sha256 sha384 sha512
    do
      if [[ "${dup_check,,}" == @(* $sumtype *) ]]
      then
        debug "found dup with $sumtype checksum"
        break
      fi
    done
    if [[ -n "$sumtype" ]]
    then
      # checksum is longest string in error message
      csum=""
      for word in $dup_check # DO NOT QUOTE THIS VAR
      do
        (( ${#word} > ${#csum} )) && csum=$word
      done
      csum=${csum//*(\')*(\")} # remove quotes from string
      debug "Search for file with $sumtype = $csum"
      response=$( \
        curl -Ls -G --request GET --user "$user":"$pass" \
          --url "$api/artifacts/" \
          -d "${sumtype}=${csum}" \
        | jq '.results[0]'
      )
      debug "dup search response" "$( jq "." <<<"$response" )"
    fi
    if [[ -z "$response" || "$response" == "null" ]]
    then
      echo "package '$package' already exists but can't find artifact :/"
      continue
    else
      echo "package '$package' already exists; reusing existing artifact"
    fi
  fi
  package_href=$( jq -r '.pulp_href' <<<"$response" )
  debug "Package href is $package_href"

  # key in artifact array will be relative name for repo
  artifacts[$( basename "$package" )]=$package_href
done

########################################
# add artifact to repo
# build JSON content units to add
units=()
for artifact_name in "${!artifacts[@]}"
do
  debug "Attempting to add '$artifact_name'"
  #TODO: get latest repository version & check if artifact is already inside
  response=$( \
    curl -Ls --request POST --user "$user":"$pass" \
      --url "$api/content/rpm/packages/" \
      -d "artifact=${artifacts[$artifact_name]}" \
      -d "relative_path=${artifact_name}" \
      -d "repository=${repo_url}" \
  )
  debug "repo add response" "$( jq . <<<"$response" )"
  task_path=$( jq -r '.task' <<<"$response" )
  # TODO: add logic to check is task_path is null
  task_url=$base/${task_path#/}
  wait_for_task "$task_url"
  repo_version=$( \
    curl -Ls --request GET --user "$user":"$pass" \
      --url "$task_url" \
    | jq -r '.created_resources[] 
             | select( . | contains("repositories/rpm/rpm") )
    '
  )
done

########################################
# create publication for repo version
response=$( \
  curl -Ls --request POST --user "$user":"$pass" \
    --url "$api/publications/rpm/rpm/" \
    -d "repository_version=$repo_version" \
    -d "gpgcheck=0" \
    -d "repo_gpgcheck=0" \
)
debug "publication response" "$( jq . <<<"$response" )"
task_path=$( jq -r '.task' <<<"$response" )
task_url=$base/${task_path#/}
wait_for_task "$task_url"
publication=$( \
  curl -Ls --request GET --user "$user":"$pass" \
    --url "$task_url" \
  | jq -r '.created_resources[] 
           | select( . | contains("publications/rpm/rpm") )
  '
)

########################################
# update distribution with publication
# first, find existing publication or create if needed
response=$( \
  curl -Ls -G --request GET --user "$user":"$pass" \
    --url "$api/distributions/rpm/rpm/" \
    -d "base_path=$distro_base_path" \
    -d "name=$distro_name" \
)
debug "distribution search response" "$( jq . <<<"$response" )"
if (( 0 >= $( jq -r '.count' <<<"$response" ) ))
then
  # no distribution; create one
  response=$( \
    curl -Ls --request POST --user "$user":"$pass" \
      --url "$api/distributions/rpm/rpm/" \
      -H "Content-Type: application/json" \
      -d '{
        "base_path": "'"$distro_base_path"'",
        "name": "'"$distro_name"'"
      }'
  )
  debug "distribution add response" "$( jq . <<<"$response" )"
  task_path=$( jq -r '.task' <<<"$response" )
  task_url=$base/${task_path#/}
  wait_for_task "$task_url"
  distro=$( \
    curl -Ls --request GET --user "$user":"$pass" \
      --url "$task_url" \
    | jq -r '.created_resources[] 
             | select( . | contains("distributions/rpm/rpm") )
    '
  )
else
  distro=$( jq -r '.results[0].pulp_href' <<<"$response" )
fi

response=$( \
  curl -Ls --request PATCH --user "$user":"$pass" \
    --url "$base/${distro#/}" \
    -H "Content-Type: application/json" \
    -d '{
      "publication": "'"$publication"'"
    }'
task_path=$( jq -r '.task' <<<"$response" )
task_url=$base/${task_path#/}
wait_for_task "$task_url"
