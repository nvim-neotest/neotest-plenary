#!/bin/bash

script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

tempfile="$SCRIPT_DIR/.test_output.tmp"

results_file=$1

if [[ -n $2 ]]; then
  nvim --headless -u $script_dir/init.lua --noplugin -c "lua _run_tests({results = '$1', file = '$2', filter = ${3:-nil}})" | tee "${tempfile}"
else
	nvim --headless -u $script_dir/init.lua --noplugin -c "PlenaryBustedDirectory tests/ {minimal_init = '$script_dir/init.lua'}" | tee "${tempfile}"
fi

# Plenary doesn't emit exit code 1 when tests have errors during setup
errors=$(sed 's/\x1b\[[0-9;]*m//g' "${tempfile}" | awk '/(Errors|Failed) :/ {print $3}' | grep -v '0')

rm "${tempfile}"

if [[ -n $errors ]]; then
  exit 1
fi

exit 0

