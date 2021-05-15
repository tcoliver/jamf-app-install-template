#!/bin/bash

PROJECT_ROOT="$( cd "$( dirname "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null )" &> /dev/null && pwd )"
BKP_DIR="${PROJECT_ROOT}/utils/bkp/"
TEMPLATE="${PROJECT_ROOT}/download_install_template.sh"

if [[ ! -d "${BKP_DIR}" ]]; then mkdir "${BKP_DIR}"; fi

START_MATCH="^# START: USER MODIFIABLE #$"
END_MATCH="^# END: USER MODIFIABLE   #$"
TEMPLATE_BEGIN=$"$(sed "/${START_MATCH}/,\$d" "${TEMPLATE}")"
TEMPLATE_END=$"$(sed "1,/${END_MATCH}/d" "${TEMPLATE}")"
if [[ -z "${TEMPLATE_BEGIN}" || -z "${TEMPLATE_END}" ]]; then exit 1; fi

while read -r example; do 
  echo "Backing up ${example}"
  cp -f "${example}" "${PROJECT_ROOT}/utils/bkp/$(basename "${example}")"

  echo "Rebuilding \"${example}\""
  config=$(sed -n "/${START_MATCH}/,/${END_MATCH}/p" "${example}")
  if [[ -z ${config} ]]; then exit 2; fi
  echo "${TEMPLATE_BEGIN}" > "${example}"
  echo "${config}" >> "${example}"
  echo "${TEMPLATE_END}" >> "${example}"
done < <(find "${PROJECT_ROOT}/examples" -name "*.sh" -maxdepth 1 -depth 1)