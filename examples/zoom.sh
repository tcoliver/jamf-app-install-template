#!/bin/bash
#
# Template Version 1.0.0
#
# This template downloads and installs applications from DMG, PKG, or ZIP based
# installers. To use the template, modify the variables in the USER MODIFIABLE
# section as needed. Include any default configuration steps in
# the configure function. Include logic for skipping the installation in the
# preinstall function
#
# Configuration
#
# | Variable           | Required | Type     | Default         | Description                                           |
# |====================|==========|==========|=================|=======================================================|
# | `APPLICATION_NAME` | true     | `string` |                 | Common name of the application, used only for         |
# |                    |          |          |                 | logging                                               |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `DOWNLOAD_URL`     | true     | `string` |                 | The URL to download from, can be indirect             |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `CONTAINER_TYPE`   | true     | `string` |                 | Extension to use for the downloaded container         |
# |                    |          |          |                 | (dmg, pkg, zip, app)                                  |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `INSTALL_ACTION`   | true     | `string` |                 | Action to install from container (run, move)          |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `INSTALLER_NAME`   | false    | `string` |                 | Name of installer with extention included. Required   |
# |                    |          |          |                 | for dmg or zip containers.                            |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `INSTALLER_TYPE`   | false    | `string` |                 | Type of installer (pkg, app, or dir). Required for    |
# |                    |          |          |                 | dmg or zip container types                            |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `INSTALLED_PATH`   | false    | `string` | NULL            | Full path of the .app package after installation      |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `DETECTION_NAME`   | false    | `string` | $INSTALLED_PATH | Running process name to detect                        |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `SCRATCH_PREFIX`   | false    | `bool`   | $TEMPDIR        | Directory to store temporary files                    |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `RELAUNCH`         | false    | `bool`   | true            | Relaunch app after install (true or false)            |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `RELAUNCH_ARGS`    | false    | `array`  | ()              | Arguments to pass when relaunching the application    |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
# | `FAIL_ON_SKIP`     | false    | `bool`   | true            | If " true" then return non-zero exit code on skip     |
# |--------------------|----------|----------|-----------------|-------------------------------------------------------|
#
# | Function           | Description                                                                                   |
# |====================|===============================================================================================|
# | `preinstall`       | Logic to determine if the script should cancel the install. You can also include any          |
# |                    | step needed before the install occurs. Returning non-zero will cancel install.                |
# |--------------------|-----------------------------------------------------------------------------------------------|
# | `postinstall`      | Configuration steps to run after the install completes. Returning non-zero will fail install. |
# |--------------------|-----------------------------------------------------------------------------------------------|
#
# Important Note: Return non-zero from the `preinstall` function to cancel the install.
#
# Exit Codes:
#   0   Successful installation
#   1   Generic error
#   2   Error in configuration
#   3   Error downloading installer
#   4   Error preparing install environment
#   5   Error while installing
#   6   preinstall function caused skipped execution while FAIL_ON_SKIP="true"
#
# Author: Trenten Oliver, UNF 2021
# Source: https://github.com/tcoliver/jamf-app-install-template
set -e
set -u

########################################
# START: USER MODIFIABLE
APPLICATION_NAME="zoom.us"
DOWNLOAD_URL="https://zoom.us/client/latest/ZoomInstallerIT.pkg"
CONTAINER_TYPE="pkg"
INSTALL_ACTION="run"
INSTALLER_NAME=
INSTALLER_TYPE=
INSTALLED_PATH="/Applications/zoom.us.app"
DETECTION_NAME=
SCRATCH_PREFIX=
RELAUNCH=
RELAUNCH_ARGS=()
FAIL_ON_SKIP=

# Return non-zero if the script should skip and try again later
preinstall() {
  KB_IN=
  KB_OUT=
  while IFS=',' read -r -a row; do
    KB_IN=$((row[2] / 1024))
    KB_OUT=$((row[3] / 1024))
    echo "zoom.us network usage | KB In: ${KB_IN} / KB Out: ${KB_OUT}"
  done < <(nettop -p zoom.us -P -n -J bytes_in,bytes_out -L 1 | tail -n +2)

  if [[ KB_IN -gt 500 || KB_OUT -gt 500 ]]; then
    echo "Zoom Meeting detected, unable to proceed"
    return 0 # do not run download and install
  else
    echo "No Zoom Meeting detected, proceeding with installation"
    return 1 # run download and install
  fi
  return 0 # run installation
}

# Add any configuration steps here
postinstall() {
  echo "Setting default configuration"
  defaults write /Library/Preferences/us.zoom.config.plist ZAutoSSOLogin -string YES
  defaults write /Library/Preferences/us.zoom.config.plist ZSSOHost -string XXX.zoom.us
  defaults write /Library/Preferences/us.zoom.config.plist nogoogle -string 1
  defaults write /Library/Preferences/us.zoom.config.plist nofacebook -string 1
  return 0
}

# END: USER MODIFIABLE
########################################

########################################
# Create a logging file and copy all stdout and stderr to it.
# Globals:
#   LOG_FILE
# Outputs:
#   Writes the beginning of a log file to stdout if one does not already exist.
########################################
function setup_logging() {
  if [[ ! -e "${LOG_FILE}" ]]; then
    if ! touch "${LOG_FILE}"; then
      echo "Failed to make log file"
      return 1
    fi
  fi
  exec > >(tee -a "${LOG_FILE}") 2>&1
  return 0
}

########################################
# Make string lowercase with underscores
########################################
slugify() {
  local app_name=$1
  echo "${app_name}" | tr '[:upper:]' '[:lower:]' | tr -s " \t" "_"
}

########################################
# Make string lowercase
########################################
lowercase() {
  local app_name=$1
  echo "${app_name}" | tr '[:upper:]' '[:lower:]'
}

########################################
# Ensure required variables exist
# Gloabls:
#   APPLICATION_NAME
#   DOWNLOAD_URL
#   CONTAINER_TYPE
#   INSTALL_ACTION
#   INSTALLER_TYPE
#   INSTALLER_NAME
#   INSTALLED_PATH
# Returns:
#   0 all required variables are set
#   1 missing required variables found
########################################
vars_check_required() {
  local SUCCESS REQUIRED_VARS

  SUCCESS="TRUE"
  REQUIRED_VARS=(
    "APPLICATION_NAME"
    "DOWNLOAD_URL"
    "CONTAINER_TYPE"
    "INSTALL_ACTION"
  )

  if [[ "${CONTAINER_TYPE}" =~ ^(dmg|zip)$ ]]; then
    REQUIRED_VARS+=("INSTALLER_TYPE" "INSTALLER_NAME" "INSTALLED_PATH")
  elif [[ -n "${INSTALLER_TYPE}" ]] || [[ -n "${INSTALLER_NAME}" ]]; then
    REQUIRED_VARS+=("INSTALLER_TYPE" "INSTALLER_NAME")
  fi

  for VARIABLE in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!VARIABLE}" ]]; then
      echo >&2 "Missing Required Variable: ${VARIABLE}"
      SUCCESS="FALSE"
    fi
  done

  if [[ "${SUCCESS}" = "TRUE" ]]; then
    return 0
  else
    return 1
  fi
}

########################################
# Check validity of supplied variables
# Gloabls:
#   CONTAINER_TYPE
#   INSTALLER_TYPE
#   INSTALL_ACTION
#   RELAUNCH
#   FAIL_ON_SKIP
# Returns:
#   0 all variables are valid
#   1 errors found in variables
########################################
vars_check_validity() {
  local SUCCESS="TRUE"

  # normalize to lowercase
  CONTAINER_TYPE=$(lowercase "${CONTAINER_TYPE}")
  INSTALLER_TYPE=$(lowercase "${INSTALLER_TYPE}")
  INSTALL_ACTION=$(lowercase "${INSTALL_ACTION}")
  RELAUNCH=$(lowercase "${RELAUNCH}")
  FAIL_ON_SKIP=$(lowercase "${FAIL_ON_SKIP}")

  if [[ ! "${CONTAINER_TYPE}" =~ ^(pkg|dmg|zip|app)$ ]]; then
    echo >&2 "Invalid Variable: CONTAINER_TYPE (Must be \"dmg\", \"pkg\", \"zip\", or \"app\")"
    SUCCESS="FALSE"
  fi

  if [[ -n "${INSTALLER_TYPE}" ]] && [[ ! "${INSTALLER_TYPE}" =~ ^(pkg|app|dir)$ ]]; then
    echo >&2 "Invalid Variable: INSTALLER_TYPE (Must be \"pkg\", \"app\", or \"dir\")"
    SUCCESS="FALSE"
  fi

  if [[ ! "${INSTALL_ACTION}" =~ ^(move|run)$ ]]; then
    echo >&2 "Invalid Variable: INSTALL_ACTION (Must be \"move\" or \"run\")"
    SUCCESS="FALSE"
  fi

  if [[ "${SUCCESS}" = "TRUE" ]]; then
    return 0
  else
    return 1
  fi
}

########################################
# Compute missing optional and dynamic variables
########################################
vars_compute_missing() {
  # Compute optional variables
  CONTAINER_NAME="$(slugify "${APPLICATION_NAME}").${CONTAINER_TYPE}"
  [[ -z "${INSTALLER_TYPE}" ]] && INSTALLER_TYPE="${CONTAINER_TYPE}"
  [[ -z "${INSTALLER_NAME}" ]] && INSTALLER_NAME="${CONTAINER_NAME}"
  [[ -z "${INSTALLED_PATH}" ]] && INSTALLED_PATH=""
  [[ -z "${DETECTION_NAME}" ]] && DETECTION_NAME="${INSTALLED_PATH}"
  [[ -z "${RELAUNCH}" ]] && RELAUNCH="true"
  [[ -z "${RELAUNCH_ARGS[*]-}" ]] && RELAUNCH_ARGS=()
  [[ -z "${FAIL_ON_SKIP}" ]] && FAIL_ON_SKIP="true"
  PROCESS_KILLED="false"

  # Compute dynamic variables
  LOG_FILE="/Library/Logs/$(slugify "${APPLICATION_NAME}")_install.log"

  if [[ "${INSTALLER_TYPE}" = "app" ]]; then
    # mktemp unsafe mode is required for opening .apps from the scratch directory
    if [[ -n "${SCRATCH_PREFIX}" ]]; then
      SCRATCH_PREFIX="$(echo "${SCRATCH_PREFIX}" | sed -E -e 's/\/+$//')"
      SCRATCH_DIR=$(mktemp -d -u "${SCRATCH_PREFIX}/dlinstall.XXXXXXXX")
    else
      SCRATCH_DIR=$(mktemp -d -u -t "dlinstall")
    fi
    if ! mkdir -p "${SCRATCH_DIR}"; then
      echo "Cannot create scratch directory"
      return 1
    fi
  else
    if [[ -n "${SCRATCH_PREFIX}" ]]; then
      SCRATCH_PREFIX="$(echo "${SCRATCH_PREFIX}" | sed -E -e 's/\/+$//')"
      if ! SCRATCH_DIR=$(mktemp -d "${SCRATCH_PREFIX}/dlinstall.XXXXXXXX"); then
        echo "Cannot create scratch directory"
        return 1
      fi
    else
      if ! SCRATCH_DIR=$(mktemp -d -t "dlinstall"); then
        echo "Cannot create scratch directory"
        return 1
      fi
    fi
  fi
  DOWNLOAD_PATH="${SCRATCH_DIR}/${CONTAINER_NAME}"
  INSTALLER_PATH="${DOWNLOAD_PATH}"
  if [[ "${CONTAINER_TYPE}" =~ ^(dmg|zip)$ ]]; then
    EXPAND_DIR="${SCRATCH_DIR}/expand_$(slugify "${APPLICATION_NAME}")"
    INSTALLER_PATH="${EXPAND_DIR}/${INSTALLER_NAME}"
  else
    EXPAND_DIR=
    INSTALLER_PATH="${DOWNLOAD_PATH}"
  fi
  return 0
}

########################################
# Dertermine if a function has been modified and echo it
# Outputs:
#   Writes function body to stout
########################################
echo_function() {
  local func_name=$1
  local func_expected=$2
  local func_body

  func_body=$(declare -f "${func_name}")

  if [[ "${func_body}" != "${func_expected}" ]]; then
    echo "\"${func_name}\" function modified"
    printf '%s\n' "${func_body}"
  else
    echo "\"${func_name}\" function not modified"
  fi
}

########################################
# Echo the global config variables to the log.
# Outputs:
#   Writes configuration variables and custom functions to stdout
########################################
echo_config() {
  VAR_NAMES=(
    "APPLICATION_NAME"
    "DOWNLOAD_URL"
    "TEMP_DIR"
    "DOWNLOAD_PATH"
    "EXPAND_DIR"
    "CONTAINER_NAME"
    "CONTAINER_TYPE"
    "INSTALLER_NAME"
    "INSTALLER_TYPE"
    "INSTALLER_PATH"
    "INSTALL_ACTION"
    "INSTALLED_PATH"
    "DETECTION_NAME"
    "SCRATCH_PREFIX"
    "RELAUNCH"
    "RELAUNCH_ARGS[*]"
    "FAIL_ON_SKIP"
    "LOG_FILE"
  )

  echo "Configurable Variables"
  echo "============================================================"
  for VAR_NAME in "${VAR_NAMES[@]}"; do
    [[ -n "${!VAR_NAME-}" ]] && printf "%-20s %s\n" "${VAR_NAME}" "${!VAR_NAME-}"
  done

  echo "Configurable Functions"
  echo "============================================================"
  echo_function "preinstall" $'preinstall () \n{ \n    return 0\n}'
  echo_function "postinstall" $'postinstall () \n{ \n    return 0\n}'
}

########################################
# Verify configuration before running
########################################
check_config() {
  local SUCCESS="TRUE"

  if ! vars_check_required; then SUCCESS="FALSE"; fi
  if ! vars_check_validity; then SUCCESS="FALSE"; fi
  if ! vars_compute_missing; then SUCCESS="FALSE"; fi

  if [[ "${SUCCESS}" = "TRUE" ]]; then
    return 0
  else
    return 1
  fi
}

########################################
# Download installer from DOWNLOAD_URL
# Parameters:
#   URL for download
#   Full path for downloaded file
# Returns:
#   0 if the installer downloaded sucessfully
#   1 if the installer failed to download
########################################
download_installer() {
  local DL_URL=$1
  local DL_PATH=$2
  echo -n "Downloading installer..."
  if ! /usr/bin/curl -L -s -o "${DL_PATH}" "${DL_URL}" >/dev/null 2>&1; then
    echo "failed. Error while downloading"
    return 1
  elif [[ ! -f "${DL_PATH}" ]]; then
    echo "failed. Downloaded installer not found."
    return 1
  else
    echo "complete"
    return 0
  fi
}

########################################
# Detect if the application is currently running
# Parameters:
#   Application for detection
# Returns:
#   0 if the application is detected as running
#   1 if the application is not detected as running
########################################
detect_running_process() {
  local PROCESS_PATH=$1

  echo -n "Detecting if ${PROCESS_PATH} is running..."
  local is_running=
  is_running=$(osascript -e "if application \"${PROCESS_PATH}\" is running then" -e "return true" -e "end if")
  if [[ "${is_running}" = "true" ]]; then
    echo "detected"
    return 0
  else
    echo "not detected"
    return 1
  fi
}

########################################
# Kill process
# Parameters:
#   Application to quit
# Returns:
#   0 if the application is detected as installed
#   1 if the application is not detected as installed
########################################
kill_running_process() {
  local PROCESS_PATH=$1
  echo -n "Killing process..."
  if osascript -e "quit app \"${PROCESS_PATH}\""; then
    PROCESS_KILLED="true"
  else
    echo "failed"
    return 1
  fi
  echo "done"
  return 0
}

########################################
# Detect if the application is installed
# Parameters:
#   Path to application to detect
# Returns:
#   0 if the application is detected as installed
#   1 if the application is not detected as installed
########################################
detect_installed_app() {
  local APP_PATH=$1

  echo -n "Detecting if ${APP_PATH} is installed..."
  if [[ -d "${APP_PATH}" ]]; then
    echo "detected"
    return 0
  else
    echo "not detected"
    return 1
  fi
}

########################################
# Remove the application's current install
# Parameters:
#   Path to application to remove
# Returns:
#   0 if the application was successfuly removed
#   1 if the application was not successfuly removed
########################################
remove_installed_app() {
  local APP_PATH=$1

  echo -n "Removing ${APP_PATH}..."
  if ! rm -rf "${APP_PATH}"; then
    echo "failed"
    return 1
  fi
  echo "done"
  return 0
}

########################################
# Copies application from download and sets permissions
# Parameters:
#   Source path
#   Destination path
# Returns:
#   0 if the application was moved successfuly
#   1 if the application was not moved successfuly
########################################
install_move() {
  local SRC_PATH=$1
  local DEST_PATH=$2

  echo "Moving \"${SRC_PATH}\" to \"${DEST_PATH}\""
  if ! mv -f "${SRC_PATH}" "${DEST_PATH}"; then
    echo "Failed to move"
    return 1
  fi
  /bin/sleep 1

  echo "Setting permissions"
  if ! chown -R root:wheel "${INSTALLED_PATH}"; then
    return 1
  fi

  echo "Removing quarantine attribute"
  xattr -r -d com.apple.quarantine "${INSTALLED_PATH}"

  return 0
}

########################################
# Installs application by running the installer
# Parameters:
#   path to installer
#   type of installer (app or pkg)
# Returns:
#   0 if the application was installed successfuly
#   1 if the application was not installed successfuly
########################################
install_run() {
  local INST_PATH=$1
  local INST_TYPE=$2

  if [[ "$INST_TYPE" = "app" ]]; then
    if ! open -W -j "${INST_PATH}"; then
      return 1
    fi
  elif [[ "$INST_TYPE" = "pkg" ]]; then
    if ! /usr/sbin/installer -pkg "${INST_PATH}" -target "/"; then
      return 1
    fi
  else
    echo "Unknown installer type (${INST_TYPE})"
    return 1
  fi
  return 0
}

################################################################################
# Cleanup all temporary files and directories
# Arguments:
#   return value of trapped signal
# Globals:
#   EXPAND_DIR
#   DOWNLOAD_PATH
#   LOG_FILE
################################################################################
cleanup() {
  local errorlevel="${1}"
  echo -n "Cleaning up from install..."

  if [ -d "${EXPAND_DIR}" ]; then
    /usr/bin/hdiutil detach -quiet "${EXPAND_DIR}" >/dev/null
    sleep 5
    /bin/rm -fR "${EXPAND_DIR}"
  fi

  if [[ -f "${DOWNLOAD_PATH}" ]]; then
    /bin/rm -f "${DOWNLOAD_PATH}"
  fi

  if [[ -d "${SCRATCH_DIR}" ]]; then
    /bin/rm -fR "${SCRATCH_DIR}"
  fi

  echo "complete"
  if [[ "${errorlevel}" -gt 0 ]]; then
    echo "Script exited with errors (errorlevel ${errorlevel})"
    case "${errorlevel}" in
      1) echo "An error in the script configuration caused the program to halt." ;;
      2) echo "An error occured while downloading the installer." ;;
      3) echo "An error occured while preparing the installation environment." ;;
      4) echo "An error occured while installing the application." ;;
      5) echo "The preinstall function caused the installation to be skipped execution while FAIL_ON_SKIP=\"true\"" ;;
      *) echo "A unknown error occurred" ;;
    esac
  fi
  {
    echo -n "Run Completed: "
    date +"%FT%T%z"
    echo "====================================="
  } >>"${LOG_FILE}"
}

########################################
# main
########################################
trap 'cleanup "${?}"' EXIT

if ! check_config; then
  exit 1
fi

setup_logging
date +"%FT%T%z" >>"${LOG_FILE}"
echo_config

if ! preinstall; then
  echo -n "The preinstall function canceled the install, exiting "
  if [[ "${FAIL_ON_SKIP}" = "true" ]]; then
    echo "failure on skip"
    exit 5
  else
    echo "success on skip"
    exit 0
  fi
fi

echo "Start: Download and install of ${APPLICATION_NAME}"

# Download installer
if ! download_installer "${DOWNLOAD_URL}" "${DOWNLOAD_PATH}"; then
  echo "Failed to download installer"
  exit 2
fi

# Prepare for installation
if [[ -n "${DETECTION_NAME}" ]]; then
  if detect_running_process "${DETECTION_NAME}"; then
    echo "Will relaunch application after install"
    RELAUNCH="true"
    if ! kill_running_process "${DETECTION_NAME}"; then
      echo "Unable to kill running process. Exiting"
      exit 3
    fi
  else
    RELAUNCH="false"
  fi
fi
if [[ "${INSTALLER_TYPE}" != "pkg" ]] && [[ -n "${INSTALLED_PATH}" ]]; then
  if detect_installed_app "${INSTALLED_PATH}"; then
    if ! remove_installed_app "${INSTALLED_PATH}"; then
      echo "Failed to remove installed app"
      exit 3
    fi
  fi
fi
# TODO add detection for same version

# Expand Archive
if [[ "${CONTAINER_TYPE}" = "dmg" ]]; then
  echo "Mounting dmg to ${EXPAND_DIR}"
  mkdir -p "${EXPAND_DIR}"
  if ! /usr/bin/hdiutil attach "${DOWNLOAD_PATH}" -mountpoint "${EXPAND_DIR}" -nobrowse -noverify -noautoopen >/dev/null; then
    echo "Failed to mount dmg"
    exit 4
  fi
elif [[ "${CONTAINER_TYPE}" = "zip" ]]; then
  echo -n "Unzipping zip to \"${EXPAND_DIR}\"..."
  if ! unzip "${DOWNLOAD_PATH}" -d "${EXPAND_DIR}" >/dev/null; then
    echo "Failed to unzip"
    exit 4
  fi
  echo "done"
fi
# Run installer
echo "Installing from \"${INSTALLER_PATH}\""
if [[ "${INSTALL_ACTION}" = "run" ]]; then
  if ! install_run "${INSTALLER_PATH}" "${INSTALLER_TYPE}"; then
    exit 4
  fi
elif [[ "${INSTALL_ACTION}" = "move" ]]; then
  if ! install_move "${INSTALLER_PATH}" "${INSTALLED_PATH}"; then
    exit 4
  fi
fi

# Post install configuration
configure

# Relauch app if required
if [[ "${RELAUNCH}" = "true" ]] && [[ "${PROCESS_KILLED}" = "true" ]]; then
  echo "Relaunching application"
  open "${INSTALLED_PATH}" --args "${RELAUNCH_ARGS[@]-}"
fi

echo "End: Download and install of ${APPLICATION_NAME}"

exit 0
