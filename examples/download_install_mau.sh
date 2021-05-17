#!/bin/bash
#
# This template downloads and installs applications from DMG, PKG, or ZIP based
# installers. To use the template, modify the variables in the USER MODIFIABLE
# section as needed. Include any default configuration steps in
# the configure function. Include logic for skipping the installation in the
# dont_run function
#
# | Variable           | Type     | Description
# | :----------------- | :------- | :----------------------------------------------------- |
# | `APPLICATION_NAME` | `string` | Common name of the application, used only for logging  |
# | `INSTALL_PATH`     | `string` | Full path of the .app package after installation       |
# | `URL`              | `string` | Download URL, can be indirect                          |
# | `DOWNLOAD_EXT`     | `string` | Extension of the downloaded installer (dmg, pkg, zip)  |
# | `RELAUNCH`         | `bool`   | Relaunch app after install (true or false)             |
# | `RELAUNCH_ARGS`    | `array`  | Arguments to pass when relaunching the application     |
# | `FAIL_ON_SKIP`     | `bool`   | If "true" then return non-zero exit code on skip       |
#
# | Function           | Description                                                       |
# | :----------------- | :---------------------------------------------------------------- |
# | `configure`        | Configuration steps to run after the install completes            |
# | `dont_run`         | Logic to determine if the script should cancel the install        |
#
# Important Note: Return 0 from the `dont_run` function to cancel the install. Returning
#                 anything other than 0 (e.g., return 1) will allow the script to continue.
#                 The script continues by default.
#
# Author: Trenten Oliver, UNF 2021
# Source: https://github.com/tcoliver/jamf-app-install-template

##########################
# START: USER MODIFIABLE #
APPLICATION_NAME="Microsoft AutoUpdate"
INSTALL_PATH=""
URL="https://go.microsoft.com/fwlink/p/?linkid=830196"
DOWNLOAD_EXT="pkg"
RELAUNCH="false"
RELAUNCH_ARGS=()
FAIL_ON_SKIP="true"

# Add any configuration steps here
function configure() {
  echo "Setting default configuration"
  # Include any default configuration steps here
  # ...
  # defaults write com.example.plist key value
}

# Return 0 if the script should skip and try again later
function dont_run() {
  # Add logic to determine if the install should be canceled.
  # ...
  # if [[ example_condition ]]; then
  #   # Script should cancel installation
  #   return 0 # dont run installation
  # fi
  return 1 # run installation
}
# END: USER MODIFIABLE   #
##########################

DOWNLOAD_EXT=$(echo "${DOWNLOAD_EXT}" | tr '[:upper:]' '[:lower:]')
if [[ ! "${DOWNLOAD_EXT}" =~ ^(pkg|dmg|zip)$ ]]; then
  echo "Invalid DOWNLOAD_EXT (${DOWNLOAD_EXT}). Must be \"dmg\", \"pkg\", or \"zip\""
  exit 5
fi

INSTALL_DIR=$(echo "${INSTALL_PATH}" | sed -En -e 's/(.+\/)[^\/]+/\1/p')
INSTALL_APP=$(echo "${INSTALL_PATH}" | sed -En -e 's/.+\/([^\/]+)/\1/p')
if [[ "${DOWNLOAD_EXT}" != "pkg" && (-z "${INSTALL_PATH}" || -z "${INSTALL_DIR}" || -z "${INSTALL_APP}") ]]; then
  echo "INSTALL_PATH can only be empty for pkg based installs"
  exit 6
fi

DOWNLOAD_PATH="/tmp/$(echo "${APPLICATION_NAME}" | tr -s " \t" "_").${DOWNLOAD_EXT}"
MOUNT_DIR="/private/tmp/$(echo "${APPLICATION_NAME}" | tr -s " \t" "_")/"
LOG_FILE="/Library/Logs/$(echo "${APPLICATION_NAME}" | tr -s " \t" "_")_install.log"

########################################
# Echo the global config variables to the log.
########################################
function echo_config() {
  echo "Configurable Variables"
  echo "======================"
  echo "APPLICATION_NAME=\"${APPLICATION_NAME}\""
  echo "INSTALL_PATH=\"${INSTALL_PATH}\""
  echo "URL=\"${URL}\""
  echo "DOWNLOAD_EXT=\"${DOWNLOAD_EXT}\""
  echo "RELAUNCH=\"${RELAUNCH}\""
  echo "RELAUNCH_ARGS=\"${RELAUNCH_ARGS[*]}\""
  echo "FAIL_ON_SKIP=\"${FAIL_ON_SKIP}\""
  echo "INSTALL_DIR=\"${INSTALL_DIR}\""
  echo "INSTALL_APP=\"${INSTALL_APP}\""
  echo "DOWNLOAD_PATH=\"${DOWNLOAD_PATH}\""
  echo "MOUNT_DIR=\"${MOUNT_DIR}\""
  echo "LOG_FILE=\"${LOG_FILE}\""

  echo "Configurable Functions"
  echo "======================"
  local configure_func_con
  local configure_func_exp
  configure_func_con=$(declare -f configure)
  configure_func_exp=$'configure () \n{ \n    echo \"Setting default configuration\"\n}'
  if [[ "${configure_func_con}" != "${configure_func_exp}" ]]; then
    echo "\"configure\" function modified"
    printf '%s\n' "${configure_func_con}"
  else
    echo "\"configure\" function not modified"
  fi

  local dont_run_func_con
  local dont_run_func_exp
  dont_run_func_con=$(declare -f dont_run)
  dont_run_func_exp=$'dont_run () \n{ \n    return 1\n}'
  if [[ "${dont_run_func_con}" != "${dont_run_func_exp}" ]]; then
    echo "\"dont_run\" function modified"
    printf '%s\n' "${dont_run_func_con}"
  else
    echo "\"dont_run\" function not modified"
  fi
}

########################################
# Create a logging file and copy all stdout and stderr to it.
########################################
function setup_logging() {
  if [[ ! -e "${LOG_FILE}" ]]; then
    if touch "${LOG_FILE}"; then
      echo "=====================================" >>"${LOG_FILE}"
    else
      echo "Failed to make log file"
    fi
  fi
  exec > >(tee -a "${LOG_FILE}") 2>&1
}

########################################
# Execute main download and install logic
########################################
function download_install() {
  echo "Start: Install of ${APPLICATION_NAME}"

  if [ -d "${DOWNLOAD_PATH}" ]; then
    /bin/rm -rf "${DOWNLOAD_PATH}"
    echo "Removed previous install files and folders."
  fi

  echo -n "Downloading ${APPLICATION_NAME}..."
  /usr/bin/curl -Ls -o "${DOWNLOAD_PATH}" "${URL}" >/dev/null 2>&1
  if [[ -f "${DOWNLOAD_PATH}" ]]; then
    echo "complete"
  else
    echo "failed"
    exit 1
  fi

  local process_killed="false"
  if [[ -n "${INSTALL_PATH}" ]]; then
    echo -n "Detecting if ${APPLICATION_NAME} is running..."
    IS_RUNNING=$(osascript -e "if application \"${INSTALL_PATH}\" is running then" -e "return true" -e "end if")
    if [[ "${IS_RUNNING}" = "true" ]]; then
      echo "detected"
      echo -n "Killing process..."
      osascript -e "quit app \"${INSTALL_PATH}\""
      process_killed="true"
      echo "done"
      echo "Will relaunch application after install"
    else
      echo "not detected"
    fi

    echo -n "Detecting if ${APPLICATION_NAME} is installed..."
    if [[ -d "${INSTALL_PATH}" ]]; then
      echo "detected"
      echo -n "Removing ${APPLICATION_NAME}..."
      if [[ -d "${INSTALL_PATH}" ]]; then
        if ! rm -rf "${INSTALL_PATH}"; then
          echo "failed"
          exit 3
        fi
        echo "done"
      fi
    else
      echo "not detected"
    fi
  else
    echo "INSTALL_PATH is not defined, skipping detections"
  fi

  echo "Installing from \"${DOWNLOAD_PATH}\""
  if [[ "${DOWNLOAD_EXT}" == "dmg" ]]; then
    MOUNT_DIR=$(/usr/bin/mktemp -d "${MOUNT_DIR}.XXXXXX")
    /usr/bin/hdiutil attach "${DOWNLOAD_PATH}" -mountpoint "${MOUNT_DIR}" -nobrowse -noverify -noautoopen >/dev/null
    echo "Mounted to \"${MOUNT_DIR}\""

    echo "Installing ${APPLICATION_NAME}"
    echo "Copying \"${APPLICATION_NAME}.app\" to Applications folder"
    if ! cp -R "${MOUNT_DIR}/${INSTALL_APP}.app" "${INSTALL_DIR}"; then
      echo "Failed to install"
      exit 4
    fi
    /bin/sleep 1

    echo "Setting permissions"
    chown -R root:wheel "${INSTALL_PATH}"
    chmod -R 755 "${INSTALL_PATH}"
    echo "Installation Complete"
  elif [[ "${DOWNLOAD_EXT}" == "pkg" ]]; then
    if ! sudo /usr/sbin/installer -pkg "${DOWNLOAD_PATH}" -target "/"; then
      echo "Failed to install"
      exit 4
    fi
  elif [[ "${DOWNLOAD_EXT}" == "zip" ]]; then
    echo -n "Unzipping \"${DOWNLOAD_PATH}\"..."
    if ! unzip "${DOWNLOAD_PATH}" -d "${INSTALL_DIR}" >/dev/null; then
      echo "Failed to unzip"
      exit 4
    fi
    echo "done"

    echo "Setting permissions"
    chown -R root:wheel "${INSTALL_PATH}"
    chmod -R 755 "${INSTALL_PATH}"
    echo "Installation Complete"
  fi

  configure

  if [[ "${RELAUNCH}" == "true" && "${process_killed}" == "true" ]]; then
    echo "Relaunching application"
    open "${INSTALL_PATH}" --args "${RELAUNCH_ARGS[@]}"
  fi

  echo "End: Install of ${APPLICATION_NAME}"
}

########################################
# Cleanup all temporary files and directories
# Arguments:
#   return value of trapped signal
########################################
function cleanup() {
  local errorlevel="${1}"
  echo -n "Cleaning up from install..."

  if [ -d "${MOUNT_DIR}" ]; then
    /usr/bin/hdiutil detach "${MOUNT_DIR}" >/dev/null
    /bin/rm -R "${MOUNT_DIR}"
  fi

  if [[ -f "${DOWNLOAD_PATH}" ]]; then
    /bin/rm "${DOWNLOAD_PATH}"
  fi

  echo "complete"
  if [[ "${errorlevel}" -gt 0 ]]; then
    echo "Script exited with errors (errorlevel ${errorlevel})"
    case "${errorlevel}" in
      1) echo "An error occurred when downloading the installer." ;;
      2) echo "An error occurred when killing the running process." ;;
      3) echo "An error occurred when removing the previous installation" ;;
      4) echo "The application failed to install." ;;
      5) echo "Invalid installer extension. Must be pkg, dmg, or zip" ;;
      6) echo "INSTALL_PATH can only be \"\" for pkg based installers" ;;
      7) echo "The dont_run function returned 0. Installation cancelled." ;;
      *) echo "A unknown error occurred" ;;
    esac
  fi
  date +"%FT%T%z" >>"${LOG_FILE}"
  echo "=====================================" >>"${LOG_FILE}"
}

trap 'cleanup "${?}"' EXIT
setup_logging
date +"%FT%T%z" >>"${LOG_FILE}"
echo_config
if dont_run; then
  echo -n "The dont_run function returned 0, exiting "
  if [[ "${FAIL_ON_SKIP}" = "true" ]]; then
    echo "failure on skip"
    exit 7
  else
    echo "success on skip"
    exit 0
  fi
fi
download_install

exit 0
