
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

- Download and install of PKG and DMG type application distributions
- Configurable for most applications with out modifying the script by setting variables
- Built-in support for including post installation configuration steps
- Built-in support to auto cancel an install in order to avoid disruptions
- Configurable to exit as failure or success on a canceled run
- Auto relaunch the application if it was closed during install
- Ready to deploy example installers in the examples directory

## 3. Documentation

The template can be configured for most any application install by modifying only the "User
Modifiable" section. This section includes the following global variables and functions:

### 3.1 Variables

| Variable           | Type     | Description
| :----------------- | :------- | :----------------------------------------------------- |
| `APPLICATION_NAME` | `string` | Common name of the application, used only for logging  |
| `INSTALL_PATH`     | `string` | Full path of the .app package after installation       |
| `URL`              | `string` | Download URL, can be indirect                          |
| `DOWNLOAD_EXT`     | `string` | Extension of the downloaded installer (dmg or pkg)     |
| `RELAUNCH`         | `bool`   | Relaunch app after install (true or false)             |
| `RELAUNCH_ARGS`    | `array`  | Arguments to pass when relaunching the application     |
| `FAIL_ON_SKIP`     | `bool`   | If "true" then return non-zero exit code on skip       |

### 3.2 Functions

| Function           | Description                                                       |
| :----------------- | :---------------------------------------------------------------- |
| `configure`        | Configuration steps to run after the install completes            |
| `dont_run`         | Logic to determine if the script should cancel the install        |

**Important Notes:**

- Return 0 from the `dont_run` function to cancel the install. Returning anything other than 0 (e.g., return 1) will allow the script to continue. The script continues by default.
- `INSTALL_PATH` may be left as "" for pkg installs. Doing so disables automatic detections. This can be useful for non-standard applications which do not install to /Applications/

### 3.3 An example Zoom configuration

```bash
##########################
# START: USER MODIFIABLE #
APPLICATION_NAME="zoom.us"
INSTALL_PATH="/Applications/zoom.us.app"
URL="https://zoom.us/client/latest/ZoomInstallerIT.pkg"
DOWNLOAD_EXT="PKG"
RELAUNCH="true"
RELAUNCH_ARGS=()

# Add any configuration steps here
function configure() {
    echo "Setting default configuration"
    defaults write /Library/Preferences/us.zoom.config.plist ZAutoSSOLogin -string YES
    defaults write /Library/Preferences/us.zoom.config.plist ZSSOHost -string XXX.zoom.us
    defaults write /Library/Preferences/us.zoom.config.plist nogoogle  -string 1
    defaults write /Library/Preferences/us.zoom.config.plist nofacebook -string 1
}

# Return 0 if the script should skip and try again later
function dont_run() {
    while IFS=',' read -r -a row; do
        KB_IN=$((row[2]/1024)) 
        KB_OUT=$((row[3]/1024))
        echo "zoom.us network usage | KB In: ${KB_IN} / KB Out: ${KB_OUT}"
    done < <(nettop -p zoom.us -P -n -J bytes_in,bytes_out -L 1 | tail -n +2)

    if [[ KB_IN -gt 500 || KB_OUT -gt 500 ]]; then  
        echo "Zoom Meeting detected, unable to proceed"  
        return 0 # do not run download and install
    else 
        echo "No Zoom Meeting detected, proceeding with installation"
        return 1 # run download and install
    fi
}
# END: USER MODIFIABLE   #
##########################
```

## 4. Usage

### 4.1 Run Locally

```bash
sudo chmod 755 ./download_install_zoom.sh
sudo ./download_install_zoom.sh
```

### 4.2 Jamf Pro Deployment

Scripts based on this template can be deployed easily as a Jamf Pro Policy using the standard Script and Policy workflows outlined in the [Jamf Pro Administrators Guide](https://www.jamf.com/resources/product-documentation/jamf-pro-administrators-guide/).
  
## 5. Contributing

Contributions are always welcome! Feel free to create issues or pull requests with template improvements or additional examples.

## 6. License

This project is licensed under the [MIT license](LICENSE).
