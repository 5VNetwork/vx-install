#!/usr/bin/env bash

# The files installed by the script conform to the Filesystem Hierarchy Standard:
# https://wiki.linuxfoundation.org/lsb/fhs

# The URL of the script project is:
# https://github.com/5vnetwork/vx-install

# The URL of the script is:
# https://github.com/5vnetwork/vx-install/raw/main/install-vx.sh

# If the script executes incorrectly, go to:
# https://github.com/5vnetwork/vx-install/issues

# You can set this variable whatever you want in shell session right before running this script by issuing:
# export DAT_PATH='/usr/local/share/vx'
DAT_PATH=${DAT_PATH:-/usr/local/share/vx}

# You can set this variable whatever you want in shell session right before running this script by issuing:
# export JSON_PATH='/usr/local/etc/vx'
JSON_PATH=${JSON_PATH:-/usr/local/etc/vx}

# Set this variable only if you are starting vx with multiple configuration files:
# export JSONS_PATH='/usr/local/etc/vx'

# Set this variable only if you want this script to check all the systemd unit file:
# export check_all_service_files='yes'

# Gobal verbals

if [[ -f '/etc/systemd/system/vx.service' ]] && [[ -f '/usr/local/bin/vx' ]]; then
  VX_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=1
else
  VX_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=0
fi

# vx current version
CURRENT_VERSION=''

# vx latest release version
RELEASE_LATEST=''

# vx latest prerelease/release version
PRE_RELEASE_LATEST=''

# vx version will be installed
INSTALL_VERSION=''

# install
INSTALL='0'

# install-geodata
INSTALL_GEODATA='0'

# remove
REMOVE='0'

# help
HELP='0'

# check
CHECK='0'

# --force
FORCE='0'

# --beta
BETA='0'

# --install-user ?
INSTALL_USER=''

# --without-geodata
NO_GEODATA='0'

# --without-logfiles
NO_LOGFILES='0'

# --logrotate
LOGROTATE='0'

# --no-update-service
N_UP_SERVICE='0'

# --reinstall
REINSTALL='0'

# --version ?
SPECIFIED_VERSION=''

# --local ?
LOCAL_FILE=''

# --proxy ?
PROXY=''

# --purge
PURGE='0'

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

systemd_cat_config() {
  if systemd-analyze --help | grep -qw 'cat-config'; then
    systemd-analyze --no-pager cat-config "$@"
    echo
  else
    echo "${aoi}~~~~~~~~~~~~~~~~"
    cat "$@" "$1".d/*
    echo "${aoi}~~~~~~~~~~~~~~~~"
    echo "${red}warning: ${green}The systemd version on the current operating system is too low."
    echo "${red}warning: ${green}Please consider to upgrade the systemd or the operating system.${reset}"
    echo
  fi
}

check_if_running_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  else
    echo "error: You must run this script as root!"
    return 1
  fi
}

identify_the_operating_system_and_architecture() {
  if [[ "$(uname)" != 'Linux' ]]; then
    echo "error: This operating system is not supported."
    return 1
  fi
  case "$(uname -m)" in
  'i386' | 'i686')
    MACHINE='386'
    ;;
  'amd64' | 'x86_64')
    MACHINE='amd64'
    ;;
  'armv5tel')
    MACHINE='arm32-v5'
    ;;
  'armv6l')
    MACHINE='arm32-v6'
    grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
    ;;
  'armv7' | 'armv7l')
    MACHINE='arm32-v7a'
    grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
    ;;
  'armv8' | 'aarch64')
    MACHINE='arm64'
    ;;
  'mips')
    MACHINE='mips'
    ;;
  'mipsle')
    MACHINE='mipsle'
    ;;
  'mips64')
    MACHINE='mips64'
    lscpu | grep -q "Little Endian" && MACHINE='mips64le'
    ;;
  'mips64le')
    MACHINE='mips64le'
    ;;
  'ppc64')
    MACHINE='ppc64'
    ;;
  'ppc64le')
    MACHINE='ppc64le'
    ;;
  'riscv64')
    MACHINE='riscv64'
    ;;
  's390x')
    MACHINE='s390x'
    ;;
  *)
    echo "error: The architecture is not supported."
    return 1
    ;;
  esac
  if [[ ! -f '/etc/os-release' ]]; then
    echo "error: Don't use outdated Linux distributions."
    return 1
  fi
  # Do not combine this judgment condition with the following judgment condition.
  ## Be aware of Linux distribution like Gentoo, which kernel supports switch between Systemd and OpenRC.
  if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
    true
  elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
    true
  else
    echo "error: Only Linux distributions using systemd are supported."
    return 1
  fi
  if [[ "$(type -P apt)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
    PACKAGE_MANAGEMENT_REMOVE='apt purge'
    package_provide_tput='ncurses-bin'
  elif [[ "$(type -P dnf)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
    PACKAGE_MANAGEMENT_REMOVE='dnf remove'
    package_provide_tput='ncurses'
  elif [[ "$(type -P yum)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='yum -y install'
    PACKAGE_MANAGEMENT_REMOVE='yum remove'
    package_provide_tput='ncurses'
  elif [[ "$(type -P zypper)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
    PACKAGE_MANAGEMENT_REMOVE='zypper remove'
    package_provide_tput='ncurses-utils'
  elif [[ "$(type -P pacman)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='pacman -Syy --noconfirm'
    PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
    package_provide_tput='ncurses'
  elif [[ "$(type -P emerge)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='emerge -qv'
    PACKAGE_MANAGEMENT_REMOVE='emerge -Cv'
    package_provide_tput='ncurses'
  else
    echo "error: The script does not support the package manager in this operating system."
    return 1
  fi
}

## Demo function for processing parameters
judgment_parameters() {
  local local_install='0'
  local temp_version='0'
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
    'install')
      INSTALL='1'
      ;;
    'install-geodata')
      INSTALL_GEODATA='1'
      ;;
    'remove')
      REMOVE='1'
      ;;
    'help')
      HELP='1'
      ;;
    'check')
      CHECK='1'
      ;;
    '--without-geodata')
      NO_GEODATA='1'
      ;;
    '--without-logfiles')
      NO_LOGFILES='1'
      ;;
    '--purge')
      PURGE='1'
      ;;
    '--version')
      if [[ -z "$2" ]]; then
        echo "error: Please specify the correct version."
        return 1
      fi
      temp_version='1'
      SPECIFIED_VERSION="$2"
      shift
      ;;
    '-f' | '--force')
      FORCE='1'
      ;;
    '--beta')
      BETA='1'
      ;;
    '-l' | '--local')
      local_install='1'
      if [[ -z "$2" ]]; then
        echo "error: Please specify the correct local file."
        return 1
      fi
      LOCAL_FILE="$2"
      shift
      ;;
    '-p' | '--proxy')
      if [[ -z "$2" ]]; then
        echo "error: Please specify the proxy server address."
        return 1
      fi
      PROXY="$2"
      shift
      ;;
    '-u' | '--install-user')
      if [[ -z "$2" ]]; then
        echo "error: Please specify the install user.}"
        return 1
      fi
      INSTALL_USER="$2"
      shift
      ;;
    '--reinstall')
      REINSTALL='1'
      ;;
    '--no-update-service')
      N_UP_SERVICE='1'
      ;;
    '--logrotate')
      if ! grep -qE '\b([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\b' <<<"$2"; then
        echo "error: Wrong format of time, it should be in the format of 12:34:56, under 10:00:00 should be start with 0, e.g. 01:23:45."
        exit 1
      fi
      LOGROTATE='1'
      LOGROTATE_TIME="$2"
      shift
      ;;
    *)
      echo "$0: unknown option -- -"
      return 1
      ;;
    esac
    shift
  done
  if ((INSTALL + INSTALL_GEODATA + HELP + CHECK + REMOVE == 0)); then
    INSTALL='1'
  elif ((INSTALL + INSTALL_GEODATA + HELP + CHECK + REMOVE > 1)); then
    echo 'You can only choose one action.'
    return 1
  fi
  if [[ "$INSTALL" -eq '1' ]] && ((temp_version + local_install + REINSTALL + BETA > 1)); then
    echo "--version,--reinstall,--beta and --local can't be used together."
    return 1
  fi
}

check_install_user() {
  if [[ -z "$INSTALL_USER" ]]; then
    if [[ -f '/usr/local/bin/vx' ]]; then
      INSTALL_USER="$(grep '^[ '$'\t]*User[ '$'\t]*=' /etc/systemd/system/vx.service | tail -n 1 | awk -F = '{print $2}' | awk '{print $1}')"
      if [[ -z "$INSTALL_USER" ]]; then
        INSTALL_USER='root'
      fi
    else
      INSTALL_USER='nobody'
    fi
  fi
  if ! id "$INSTALL_USER" >/dev/null 2>&1; then
    echo "the user '$INSTALL_USER' is not effective"
    exit 1
  fi
  INSTALL_USER_UID="$(id -u "$INSTALL_USER")"
  INSTALL_USER_GID="$(id -g "$INSTALL_USER")"
}

install_software() {
  package_name="$1"
  file_to_detect="$2"
  type -P "$file_to_detect" >/dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name" >/dev/null 2>&1; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi
}

get_current_version() {
  # Get the CURRENT_VERSION
  if [[ -f '/usr/local/bin/vx' ]]; then
    CURRENT_VERSION="$(/usr/local/bin/vx -version | awk 'NR==1 {print $2}')"
    CURRENT_VERSION="v${CURRENT_VERSION#v}"
  else
    CURRENT_VERSION=""
  fi
}

get_latest_version() {
  # Get vx latest release version number
  local tmp_file
  tmp_file="$(mktemp)"
  local url='https://api.github.com/repos/5vnetwork/vx-core/releases/latest'
  if curl -x "${PROXY}" -sSfLo "$tmp_file" -H "Accept: application/vnd.github.v3+json" "$url"; then
    echo "get release list success"
  else
    "rm" "$tmp_file"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  RELEASE_LATEST="$(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')"
  if [[ -z "$RELEASE_LATEST" ]]; then
    if grep -q "API rate limit exceeded" "$tmp_file"; then
      echo "error: github API rate limit exceeded"
    else
      echo "error: Failed to get the latest release version."
      echo "Welcome bug report:https://github.com/5vnetwork/vx-install/issues"
    fi
    "rm" "$tmp_file"
    exit 1
  fi
  "rm" "$tmp_file"
  RELEASE_LATEST="v${RELEASE_LATEST#v}"
  url='https://api.github.com/repos/5vnetwork/vx-core/releases'
  if curl -x "${PROXY}" -sSfLo "$tmp_file" -H "Accept: application/vnd.github.v3+json" "$url"; then
    echo "get release list success"
  else
    "rm" "$tmp_file"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  local releases_list
  readarray -t releases_list < <(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')
  if [[ "${#releases_list[@]}" -eq 0 ]]; then
    if grep -q "API rate limit exceeded" "$tmp_file"; then
      echo "error: github API rate limit exceeded"
    else
      echo "error: Failed to get the latest release version."
      echo "Welcome bug report:https://github.com/5vnetwork/vx-install/issues"
    fi
    "rm" "$tmp_file"
    exit 1
  fi
  local i url_zip
  for i in "${!releases_list[@]}"; do
    releases_list["$i"]="v${releases_list[$i]#v}"
    url_zip="https://github.com/5vnetwork/vx-core/releases/download/${releases_list[$i]}/vx-linux-$MACHINE.zip"
    if grep -q "$url_zip" "$tmp_file"; then
      PRE_RELEASE_LATEST="${releases_list[$i]}"
      break
    fi
  done
  "rm" "$tmp_file"
}

version_gt() {
  test "$(echo -e "$1\\n$2" | sort -V | head -n 1)" != "$1"
}

download_vx() {
  local DOWNLOAD_LINK="https://github.com/5vnetwork/vx-core/releases/download/${INSTALL_VERSION}/vx-linux-${MACHINE}.zip"
  echo "Downloading vx archive: $DOWNLOAD_LINK"
  if curl -f -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
    echo "ok."
  else
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
  echo "Downloading verification file for vx archive: ${DOWNLOAD_LINK}.dgst"
  if curl -f -x "${PROXY}" -sSR -H 'Cache-Control: no-cache' -o "${ZIP_FILE}.dgst" "${DOWNLOAD_LINK}.dgst"; then
    echo "ok."
  else
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
  if grep 'Not Found' "${ZIP_FILE}.dgst"; then
    echo 'error: This version does not support verification. Please replace with another version.'
    return 1
  fi

  # Verification of vx archive
  CHECKSUM=$(awk -F '= ' '/256=/ {print $2}' "${ZIP_FILE}.dgst")
  LOCALSUM=$(sha256sum "$ZIP_FILE" | awk '{printf $1}')
  if [[ "$CHECKSUM" != "$LOCALSUM" ]]; then
    echo 'error: SHA256 check failed! Please check your network or try again.'
    return 1
  fi
}

decompression() {
  if ! unzip -q "$1" -d "$TMP_DIRECTORY"; then
    echo 'error: vx decompression failed.'
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    exit 1
  fi
  echo "info: Extract the vx package to $TMP_DIRECTORY and prepare it for installation."
}

install_file() {
  NAME="$1"
  if [[ "$NAME" == 'vx' ]]; then
    install -m 755 "${TMP_DIRECTORY}/$NAME" "/usr/local/bin/$NAME"
  elif [[ "$NAME" == 'geoip.dat' ]] || [[ "$NAME" == 'geosite.dat' ]]; then
    install -m 644 "${TMP_DIRECTORY}/$NAME" "${DAT_PATH}/$NAME"
  fi
}

install_vx() {
  # Install vx binary to /usr/local/bin/ and $DAT_PATH
  install_file vx
  # If the file exists, geoip.dat and geosite.dat will not be installed or updated
  if [[ "$NO_GEODATA" -eq '0' ]] && [[ ! -f "${DAT_PATH}/.undat" ]]; then
    install -d "$DAT_PATH"
    install_file geoip.dat
    install_file geosite.dat
    GEODATA='1'
  fi

  # Install vx configuration file to $JSON_PATH
  # shellcheck disable=SC2153
  if [[ -z "$JSONS_PATH" ]] && [[ ! -d "$JSON_PATH" ]]; then
    install -d "$JSON_PATH"
    echo "{}" >"${JSON_PATH}/config.json"
    CONFIG_NEW='1'
  fi

#   # Install vx configuration file to $JSONS_PATH
#   if [[ -n "$JSONS_PATH" ]] && [[ ! -d "$JSONS_PATH" ]]; then
#     install -d "$JSONS_PATH"
#     for BASE in 00_log 01_api 02_dns 03_routing 04_policy 05_inbounds 06_outbounds 07_transport 08_stats 09_reverse; do
#       echo '{}' >"${JSONS_PATH}/${BASE}.json"
#     done
#     CONFDIR='1'
#   fi

  # Used to store vx log files
  if [[ "$NO_LOGFILES" -eq '0' ]]; then
    if [[ ! -d '/var/log/vx/' ]]; then
      install -d -m 755 -o 0 -g 0 /var/log/vx/
      install -m 600 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /dev/null /var/log/vx/vx.log
    #   install -m 600 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /dev/null /var/log/vx/error.log
      LOG='1'
    else
      chown 0:0 /var/log/vx/
      chmod 755 /var/log/vx/
      chown "$INSTALL_USER_UID:$INSTALL_USER_GID" /var/log/vx/*.log
      chmod 600 /var/log/vx/*.log
    fi
  fi
}

install_startup_service_file() {
  mkdir -p '/etc/systemd/system/vx.service.d'
  mkdir -p '/etc/systemd/system/vx@.service.d/'
  local temp_CapabilityBoundingSet="CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
  local temp_AmbientCapabilities="AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
  local temp_NoNewPrivileges="NoNewPrivileges=true"
  if [[ "$INSTALL_USER_UID" -eq '0' ]]; then
    temp_CapabilityBoundingSet="#${temp_CapabilityBoundingSet}"
    temp_AmbientCapabilities="#${temp_AmbientCapabilities}"
    temp_NoNewPrivileges="#${temp_NoNewPrivileges}"
  fi
  cat >/etc/systemd/system/vx.service <<EOF
[Unit]
Description=vx Service
Documentation=https://github.com/5vnetwork
After=network.target nss-lookup.target

[Service]
User=$INSTALL_USER
${temp_CapabilityBoundingSet}
${temp_AmbientCapabilities}
${temp_NoNewPrivileges}
ExecStart=/usr/local/bin/vx run --config /usr/local/etc/vx/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/vx@.service <<EOF
[Unit]
Description=vx Service
Documentation=https://github.com/5vnetwork/vx-core
After=network.target nss-lookup.target

[Service]
User=$INSTALL_USER
${temp_CapabilityBoundingSet}
${temp_AmbientCapabilities}
${temp_NoNewPrivileges}
ExecStart=/usr/local/bin/vx run --config /usr/local/etc/vx/%i.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 /etc/systemd/system/vx.service /etc/systemd/system/vx@.service
#   if [[ -n "$JSONS_PATH" ]]; then
#     "rm" '/etc/systemd/system/vx.service.d/10-donot_touch_single_conf.conf' \
#       '/etc/systemd/system/vx@.service.d/10-donot_touch_single_conf.conf'
#     echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# # Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
# [Service]
# ExecStart=
# ExecStart=/usr/local/bin/vx run -confdir $JSONS_PATH" |
#       tee '/etc/systemd/system/vx.service.d/10-donot_touch_multi_conf.conf' > \
#         '/etc/systemd/system/vx@.service.d/10-donot_touch_multi_conf.conf'
#   else
    "rm" '/etc/systemd/system/vx.service.d/10-donot_touch_multi_conf.conf' \
      '/etc/systemd/system/vx@.service.d/10-donot_touch_multi_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/vx run --config ${JSON_PATH}/config.json" > \
      '/etc/systemd/system/vx.service.d/10-donot_touch_single_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/vx run --config ${JSON_PATH}/%i.json" > \
      '/etc/systemd/system/vx@.service.d/10-donot_touch_single_conf.conf'
#   fi
  echo "info: Systemd service files have been installed successfully!"
  echo "${red}warning: ${green}The following are the actual parameters for the vx service startup."
  echo "${red}warning: ${green}Please make sure the configuration file path is correctly set.${reset}"
  systemd_cat_config /etc/systemd/system/vx.service
  # shellcheck disable=SC2154
  if [[ "${check_all_service_files:0:1}" = 'y' ]]; then
    echo
    echo
    systemd_cat_config /etc/systemd/system/vx@.service
  fi
  systemctl daemon-reload
  SYSTEMD='1'
}

start_vx() {
  if [[ -f '/etc/systemd/system/vx.service' ]]; then
    systemctl start "${VX_CUSTOMIZE:-vx}"
    sleep 1s
    if systemctl -q is-active "${VX_CUSTOMIZE:-vx}"; then
      echo 'info: Start the vx service.'
    else
      echo 'error: Failed to start vx service.'
      exit 1
    fi
  fi
}

stop_vx() {
  VX_CUSTOMIZE="$(systemctl list-units | grep 'vx@' | awk -F ' ' '{print $1}')"
  if [[ -z "$VX_CUSTOMIZE" ]]; then
    local vx_daemon_to_stop='vx.service'
  else
    local vx_daemon_to_stop="$VX_CUSTOMIZE"
  fi
  if ! systemctl stop "$vx_daemon_to_stop"; then
    echo 'error: Stopping the vx service failed.'
    exit 1
  fi
  echo 'info: Stop the vx service.'
}

install_with_logrotate() {
  install_software 'logrotate' 'logrotate'
  if [[ -z "$LOGROTATE_TIME" ]]; then
    LOGROTATE_TIME="00:00:00"
  fi
  cat <<EOF >/etc/systemd/system/logrotate@.service
[Unit]
Description=Rotate log files
Documentation=man:logrotate(8)

[Service]
Type=oneshot
ExecStart=/usr/sbin/logrotate /etc/logrotate.d/%i
EOF
  cat <<EOF >/etc/systemd/system/logrotate@.timer
[Unit]
Description=Run logrotate for %i logs

[Timer]
OnCalendar=*-*-* $LOGROTATE_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF
  if [[ ! -d '/etc/logrotate.d/' ]]; then
    install -d -m 700 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /etc/logrotate.d/
    LOGROTATE_DIR='1'
  fi
  cat <<EOF >/etc/logrotate.d/vx
/var/log/vx/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0600 $INSTALL_USER_UID $INSTALL_USER_GID
}
EOF
  LOGROTATE_FIN='1'
}

install_geodata() {
  download_geodata() {
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "${dir_tmp}/${2}" "${1}"; then
      echo 'error: Download failed! Please check your network or try again.'
      exit 1
    fi
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "${dir_tmp}/${2}.sha256sum" "${1}.sha256sum"; then
      echo 'error: Download failed! Please check your network or try again.'
      exit 1
    fi
  }
  local download_link_geoip="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
  local download_link_geosite="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
  local file_ip='geoip.dat'
  local file_dlc='geosite.dat'
  local file_site='geosite.dat'
  local dir_tmp
  dir_tmp="$(mktemp -d)"
  [[ "$VX_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '0' ]] && echo "warning: vx was not installed"
  download_geodata $download_link_geoip $file_ip
  download_geodata $download_link_geosite $file_dlc
  cd "${dir_tmp}" || exit
  for i in "${dir_tmp}"/*.sha256sum; do
    if ! sha256sum -c "${i}"; then
      echo 'error: Check failed! Please check your network or try again.'
      exit 1
    fi
  done
  cd - >/dev/null || exit 1
  install -d "$DAT_PATH"
  install -m 644 "${dir_tmp}"/${file_dlc} "${DAT_PATH}"/${file_site}
  install -m 644 "${dir_tmp}"/${file_ip} "${DAT_PATH}"/${file_ip}
  rm -r "${dir_tmp}"
  exit 0
}

check_update() {
  if [[ "$VX_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '1' ]]; then
    get_current_version
    echo "info: The current version of vx is ${CURRENT_VERSION}."
  else
    echo 'warning: vx is not installed.'
  fi
  get_latest_version
  echo "info: The latest release version of vx is ${RELEASE_LATEST}."
  echo "info: The latest pre-release/release version of vx is ${PRE_RELEASE_LATEST}."
  exit 0
}

remove_vx() {
  if systemctl list-unit-files | grep -qw 'vx'; then
    if [[ -n "$(pidof vx)" ]]; then
      stop_vx
    fi
    local delete_files=('/usr/local/bin/vx' '/etc/systemd/system/vx.service' '/etc/systemd/system/vx@.service' '/etc/systemd/system/vx.service.d' '/etc/systemd/system/vx@.service.d')
    [[ -d "$DAT_PATH" ]] && delete_files+=("$DAT_PATH")
    [[ -f '/etc/logrotate.d/vx' ]] && delete_files+=('/etc/logrotate.d/vx')
    if [[ "$PURGE" -eq '1' ]]; then
      if [[ -z "$JSONS_PATH" ]]; then
        delete_files+=("$JSON_PATH")
      else
        delete_files+=("$JSONS_PATH")
      fi
      [[ -d '/var/log/vx' ]] && delete_files+=('/var/log/vx')
      [[ -f '/etc/systemd/system/logrotate@.service' ]] && delete_files+=('/etc/systemd/system/logrotate@.service')
      [[ -f '/etc/systemd/system/logrotate@.timer' ]] && delete_files+=('/etc/systemd/system/logrotate@.timer')
    fi
    systemctl disable vx
    if [[ -f '/etc/systemd/system/logrotate@.timer' ]]; then
      if ! systemctl stop logrotate@vx.timer && systemctl disable logrotate@vx.timer; then
        echo 'error: Stopping and disabling the logrotate service failed.'
        exit 1
      fi
      echo 'info: Stop and disable the logrotate service.'
    fi
    if ! ("rm" -r "${delete_files[@]}"); then
      echo 'error: Failed to remove vx.'
      exit 1
    else
      for i in "${!delete_files[@]}"; do
        echo "removed: ${delete_files[$i]}"
      done
      systemctl daemon-reload
      echo "You may need to execute a command to remove dependent software: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
      echo 'info: vx has been removed.'
      if [[ "$PURGE" -eq '0' ]]; then
        echo 'info: If necessary, manually delete the configuration and log files.'
        if [[ -n "$JSONS_PATH" ]]; then
          echo "info: e.g., $JSONS_PATH and /var/log/vx/ ..."
        else
          echo "info: e.g., $JSON_PATH and /var/log/vx/ ..."
        fi
      fi
      exit 0
    fi
  else
    echo 'error: vx is not installed.'
    exit 1
  fi
}

# Explanation of parameters in the script
show_help() {
  echo "usage: $0 ACTION [OPTION]..."
  echo
  echo 'ACTION:'
  echo '  install                   Install/Update vx'
  echo '  install-geodata           Install/Update geoip.dat and geosite.dat only'
  echo '  remove                    Remove vx'
  echo '  help                      Show help'
  echo '  check                     Check if vx can be updated'
  echo 'If no action is specified, then install will be selected'
  echo
  echo 'OPTION:'
  echo '  install:'
  echo '    --version                 Install the specified version of vx, e.g., --version v1.0.0'
  echo '    -f, --force               Force install even though the versions are same'
  echo '    --beta                    Install the pre-release version if it is exist'
  echo '    -l, --local               Install vx from a local file'
  echo '    -p, --proxy               Download through a proxy server, e.g., -p http://127.0.0.1:8118 or -p socks5://127.0.0.1:1080'
  echo '    -u, --install-user        Install vx in specified user, e.g, -u root'
  echo '    --reinstall               Reinstall current vx version'
  echo "    --no-update-service       Don't change service files if they are exist"
  echo "    --without-geodata         Don't install/update geoip.dat and geosite.dat"
  echo "    --without-logfiles        Don't install /var/log/vx"
  echo "    --logrotate [time]        Install with logrotate."
  echo "                              [time] need be in the format of 12:34:56, under 10:00:00 should be start with 0, e.g. 01:23:45."
  echo '  install-geodata:'
  echo '    -p, --proxy               Download through a proxy server'
  echo '  remove:'
  echo '    --purge                   Remove all the vx files, include logs, configs, etc'
  echo '  check:'
  echo '    -p, --proxy               Check new version through a proxy server'
  exit 0
}

main() {
  check_if_running_as_root || return 1
  identify_the_operating_system_and_architecture || return 1
  judgment_parameters "$@" || return 1

  install_software "$package_provide_tput" 'tput'
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  aoi=$(tput setaf 6)
  reset=$(tput sgr0)

  # Parameter information
  [[ "$HELP" -eq '1' ]] && show_help
  [[ "$CHECK" -eq '1' ]] && check_update
  [[ "$REMOVE" -eq '1' ]] && remove_vx
  [[ "$INSTALL_GEODATA" -eq '1' ]] && install_geodata

  # Check if the user is effective
  check_install_user

  # Check Logrotate after Check User
  [[ "$LOGROTATE" -eq '1' ]] && install_with_logrotate

  # Two very important variables
  TMP_DIRECTORY="$(mktemp -d)"
  ZIP_FILE="${TMP_DIRECTORY}/vx-linux-$MACHINE.zip"

  # Install vx from a local file, but still need to make sure the network is available
  if [[ -n "$LOCAL_FILE" ]]; then
    echo 'warn: Install vx from a local file, but still need to make sure the network is available.'
    echo -n 'warn: Please make sure the file is valid because we cannot confirm it. (Press any key) ...'
    read -r
    install_software 'unzip' 'unzip'
    decompression "$LOCAL_FILE"
  else
    get_current_version
    if [[ "$REINSTALL" -eq '1' ]]; then
      if [[ -z "$CURRENT_VERSION" ]]; then
        echo "error: vx is not installed"
        exit 1
      fi
      INSTALL_VERSION="$CURRENT_VERSION"
      echo "info: Reinstalling vx $CURRENT_VERSION"
    elif [[ -n "$SPECIFIED_VERSION" ]]; then
      SPECIFIED_VERSION="v${SPECIFIED_VERSION#v}"
      if [[ "$CURRENT_VERSION" == "$SPECIFIED_VERSION" ]] && [[ "$FORCE" -eq '0' ]]; then
        echo "info: The current version is same as the specified version. The version is ${CURRENT_VERSION}."
        exit 0
      fi
      INSTALL_VERSION="$SPECIFIED_VERSION"
      echo "info: Installing specified vx version $INSTALL_VERSION for $(uname -m)"
    else
      install_software 'curl' 'curl'
      get_latest_version
      if [[ "$BETA" -eq '0' ]]; then
        INSTALL_VERSION="$RELEASE_LATEST"
      else
        INSTALL_VERSION="$PRE_RELEASE_LATEST"
      fi
      if ! version_gt "$INSTALL_VERSION" "$CURRENT_VERSION" && [[ "$FORCE" -eq '0' ]]; then
        echo "info: No new version. The current version of vx is ${CURRENT_VERSION}."
        exit 0
      fi
      echo "info: Installing vx $INSTALL_VERSION for $(uname -m)"
    fi
    install_software 'curl' 'curl'
    install_software 'unzip' 'unzip'
    if ! download_vx; then
      "rm" -r "$TMP_DIRECTORY"
      echo "removed: $TMP_DIRECTORY"
      exit 1
    fi
    decompression "$ZIP_FILE"
  fi

  # Determine if vx is running
  if systemctl list-unit-files | grep -qw 'vx'; then
    if [[ -n "$(pidof vx)" ]]; then
      stop_vx
      VX_RUNNING='1'
    fi
  fi
  install_vx
  [[ "$N_UP_SERVICE" -eq '1' && -f '/etc/systemd/system/vx.service' ]] || install_startup_service_file
  echo 'installed: /usr/local/bin/vx'
  # If the file exists, the content output of installing or updating geoip.dat and geosite.dat will not be displayed
  if [[ "$GEODATA" -eq '1' ]]; then
    echo "installed: ${DAT_PATH}/geoip.dat"
    echo "installed: ${DAT_PATH}/geosite.dat"
  fi
  if [[ "$CONFIG_NEW" -eq '1' ]]; then
    echo "installed: ${JSON_PATH}/config.json"
  fi
#   if [[ "$CONFDIR" -eq '1' ]]; then
#     echo "installed: ${JSON_PATH}/00_log.json"
#     echo "installed: ${JSON_PATH}/01_api.json"
#     echo "installed: ${JSON_PATH}/02_dns.json"
#     echo "installed: ${JSON_PATH}/03_routing.json"
#     echo "installed: ${JSON_PATH}/04_policy.json"
#     echo "installed: ${JSON_PATH}/05_inbounds.json"
#     echo "installed: ${JSON_PATH}/06_outbounds.json"
#     echo "installed: ${JSON_PATH}/07_transport.json"
#     echo "installed: ${JSON_PATH}/08_stats.json"
#     echo "installed: ${JSON_PATH}/09_reverse.json"
#   fi
  if [[ "$LOG" -eq '1' ]]; then
    echo 'installed: /var/log/vx/'
    echo 'installed: /var/log/vx/vx.log'
  fi
  if [[ "$LOGROTATE_FIN" -eq '1' ]]; then
    echo 'installed: /etc/systemd/system/logrotate@.service'
    echo 'installed: /etc/systemd/system/logrotate@.timer'
    if [[ "$LOGROTATE_DIR" -eq '1' ]]; then
      echo 'installed: /etc/logrotate.d/'
    fi
    echo 'installed: /etc/logrotate.d/vx'
    systemctl start logrotate@vx.timer
    systemctl enable logrotate@vx.timer
    sleep 1s
    if systemctl -q is-active logrotate@vx.timer; then
      echo "info: Enable and start the logrotate@vx.timer service"
    else
      echo "warning: Failed to enable and start the logrotate@vx.timer service"
    fi
  fi
  if [[ "$SYSTEMD" -eq '1' ]]; then
    echo 'installed: /etc/systemd/system/vx.service'
    echo 'installed: /etc/systemd/system/vx@.service'
  fi
  "rm" -r "$TMP_DIRECTORY"
  echo "removed: $TMP_DIRECTORY"
  get_current_version
  echo "info: vx $CURRENT_VERSION is installed."
  echo "You may need to execute a command to remove dependent software: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
  if [[ "$VX_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '1' ]] && [[ "$FORCE" -eq '0' ]] && [[ "$REINSTALL" -eq '0' ]]; then
    [[ "$VX_RUNNING" -eq '1' ]] && start_vx
  else
    systemctl start vx
    systemctl enable vx
    sleep 1s
    if systemctl -q is-active vx; then
      echo "info: Enable and start the vx service"
    else
      echo "warning: Failed to enable and start the vx service"
    fi
  fi
}

main "$@"