
# Jamf Pro - Application Install Template

## Table of Contents

- [1. General Info](#1-general-info)
- [2. Features](#2-features)
- [3. Documentation](#3-documentation)
- [4. Usage](#4-usage)
- [5. Contributing](#5-contributing)
- [6. License](#6-license)

## 1. General Info

A bash shell template designed to make it as simple as possible to create application
install scripts that are always up to date.

## 2. Features

- Download and install of PKG, APP, DMG, and ZIP type application distributions
- Configurable for most applications by setting a few variables
- Support for including pre and post installation configuration steps
- Auto cancel an install in order to avoid disruptions
- Choose to exit as failure or success on a canceled run
- Auto relaunch the application if it was closed during install
- Ready to deploy example installers in the examples directory

## 3. Documentation

The template can be configured for most any application install by modifying only the "User
Modifiable" section. This section includes the following global variables and functions:

### 3.1 Variables

| Variable           | Required | Type     | Default         | Description                                                                    |
| :----------------- | :------- | :------- | :-------------- | :----------------------------------------------------------------------------- |
| `APPLICATION_NAME` | true     | `string` |                 | Common name of the application, used only for logging                          |
| `DOWNLOAD_URL`     | true     | `string` |                 | The URL to download from, can be indirect                                      |
| `CONTAINER_TYPE`   | true     | `string` |                 | Extension to use for the downloaded container (dmg, pkg, zip, app)             |
| `INSTALL_ACTION`   | true     | `string` |                 | Action to install from container (run, move)                                   |
| `INSTALLER_NAME`   | false    | `string` |                 | Name of installer with extention included. Required for dmg or zip containers. |
| `INSTALLER_TYPE`   | false    | `string` |                 | Type of installer (pkg, app, or dir). Required for dmg or zip container types  |
| `INSTALLED_PATH`   | false    | `string` | NULL            | Full path of the .app package after installation                               |
| `DETECTION_NAME`   | false    | `string` | $INSTALLED_PATH | Running process name to detect                                                 |
| `SCRATCH_PREFIX`   | false    | `bool`   | $TEMPDIR        | Directory to store temporary files                                             |
| `RELAUNCH`         | false    | `bool`   | true            | Relaunch app after install (true or false)                                     |
| `RELAUNCH_ARGS`    | false    | `array`  | ()              | Arguments to pass when relaunching the application                             |
| `FAIL_ON_SKIP`     | false    | `bool`   | true            | If " true" then return non-zero exit code on skip                              |

### 3.2 Functions

| Function           | Description                                                                                                                                                         |
|--------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `preinstall`       | Logic to determine if the script should cancel the install. You can also include any step needed before the install occurs. Returning non-zero will cancel install. |
| `postinstall`      | Configuration steps to run after the install completes. Returning non-zero will fail install.                                                                       |

### 3.3 An example Zoom configuration

```bash
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
```

## 4. Usage

### 4.1 Run Locally

```bash
sudo chmod u+x ./download_install_zoom.sh
sudo ./download_install_zoom.sh
```

### 4.2 Jamf Pro Deployment

Scripts based on this template can be deployed easily as a Jamf Pro Policy using the standard Script and Policy workflows outlined in the [Jamf Pro Administrators Guide](https://www.jamf.com/resources/product-documentation/jamf-pro-administrators-guide/).

## 5. Contributing

Contributions are always welcome! Feel free to create issues or pull requests with template improvements or additional examples.

## 6. License

This project is licensed under the [MIT license](LICENSE).
