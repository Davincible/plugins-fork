#!/bin/bash

MICRO_VERSION="v4"
LINTER_VERSION="v1.50.0"
GO_TEST_FLAGS="-v -race -cover -bench=."

RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
BAR="-------------------------------------------------------------------------------"

export RICHGO_FORCE_COLOR="true"
export IN_TRAVIS_CI="true"
export TRAVIS="true"

# Print a green colored message to the screen.
function print_msg() {
  printf "\n\n${GREEN}${BAR}${NC}\n"
  printf "${GREEN}| > ${1}${NC}\n"
  printf "${GREEN}${BAR}${NC}\n\n"
  sleep 1
}

# Print a red colored message to the screen.
function print_red() {
  printf "\n\n${RED}${BAR}${NC}\n"
  printf "${RED}| > ${1}${NC}\n"
  printf "${RED}${BAR}${NC}\n\n"
  sleep 1
}

# Print the contents of the directory array. 
function print_list() {
  dirs=$1

  print_msg "Found ${#dirs[@]} directories to test"
  echo "Changed dirs:"
  printf '%s \n' "${dirs[@]}"
  printf '\n\n'
  sleep 1
}

# Add a job summary to GitHub Actions.
function add_summary() {
  printf "${1}\n" >>$GITHUB_STEP_SUMMARY
}

# Find directories that contain changes.
function find_changes() {
  # Pull main branch.
  git checkout main &>/dev/null
  git checkout $GITHUB_REF_NAME &>/dev/null

  # Find all directories that have changed files.
  hash=$(git merge-base --fork-point main)
  changes=($(git diff --name-only $hash | xargs -d'\n' -I{} dirname {} | sort -u))

  changes=($(find ${changes[@]} -maxdepth 1 -name 'go.mod' -printf '%h\n'))

  echo ${changes[@]}
}

# Find all go directories.
function find_all() {
  find $MICRO_VERSION -name 'go.mod' -printf '%h\n'
}

# Run GoLangCi Linters.
function run_linter() {
  curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin $LINTER_VERSION

  golangci-lint --version

  cwd=$(pwd)
  dirs=$1
  failed="false"
  for dir in "${dirs[@]}"; do
    pushd $dir >/dev/null
    print_msg "Running linter on ${dir}"

    golangci-lint run --out-format github-actions -c "${cwd}/.golangci.yaml"

    # Keep track of exit code of linter
    if [[ $? -ne 0 ]]; then
      failed="true"
    fi

    popd >/dev/null
  done

  if [[ $failed == "true" ]]; then
    add_summary "## Autofix Linting Issues"
    add_summary "The linter can sometimes autofix some of the issues, if it is supported."
    add_summary "\`\`\`bash\ncd <your plugin>\ngolangci-lint run -c <go-micro/plugins dir>/.golangci.yaml --fix\n\`\`\`"
    print_red "Linter failed"
    exit 1
  fi
}

# Run unit tests with tparse to create a summary.
function create_summary() {
  go install github.com/mfridman/tparse@latest

  add_summary "## Test Summary"

  cwd=$(pwd)
  dirs=$1
  failed="false"
  for dir in "${dirs[@]}"; do
    pushd $dir >/dev/null
    print_msg "Creating summary for $dir"
    add_summary "\n### ${dir}\n"

    # Download all modules.
    go get -v -t -d ./...

    go test $GO_TEST_FLAGS -json ./... |
      tparse -notests -format=markdown >>$GITHUB_STEP_SUMMARY

    if [[ $? -ne 0 ]]; then
      failed="true"
    fi

    popd >/dev/null
  done

  if [[ $failed == "true" ]]; then
    print_red "Tests failed"
    exit 1
  fi
}

# Run Unit tests with RichGo for pretty output.
function run_test() {
  cwd=$(pwd)
  dirs=$1
  failed="false"

  print_msg "Downloading dependencies..."

  go install github.com/kyoh86/richgo@latest

  for dir in "${dirs[@]}"; do
	  bash -c "cd ${dir}; go mod tidy &>/dev/null" 
  done

  for dir in "${dirs[@]}"; do
    pushd $dir >/dev/null
    print_msg "Running unit tests for $dir"

    # Download all modules.
    go get -v -t -d ./...

    richgo test $GO_TEST_FLAGS ./...

    if [[ $? -ne 0 ]]; then
      failed="true"
    fi

    popd >/dev/null
  done

  if [[ $failed == "true" ]]; then
    print_red "Tests failed"
    exit 1
  fi
}

# Get the dir list based on command type.
function get_dirs() {
  if [[ $1 == "all" ]]; then
    find_all
  else
    find_changes
  fi
}

print_msg "Using branch: $GITHUB_REF_NAME"

case $1 in
"lint")
  dirs=($(get_dirs $2))
  [[ "${#dirs[@]}" -eq 0 ]] && exit 0

  print_list $dirs
  run_linter $dirs
  ;;
"test")
  dirs=($(get_dirs $2))
  [[ "${#dirs[@]}" -eq 0 ]] && exit 0

  print_list $dirs
  run_test $dirs
  ;;
"summary")
  dirs=($(get_dirs $2))
  [[ "${#dirs[@]}" -eq 0 ]] && exit 0

  print_list $dirs
  create_summary $dirs
  ;;
"")
  printf "Please provide a command [lint, test, summary]."
  exit 1
  ;;
*)
  printf "Command not found: $1. Select one of [lint, test, summary]"
  exit 1
  ;;
esac
