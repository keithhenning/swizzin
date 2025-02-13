#!/bin/bash
# whisparr v1 installer

#shellcheck source=sources/functions/utils
. /etc/swizzin/sources/functions/utils

_install_whisparr() {
    apt_install curl mediainfo sqlite3

    whisparrConfDir="/home/$whisparrOwner/.config/Whisparr"
    mkdir -p "$whisparrConfDir"
    chown -R "$whisparrOwner":"$whisparrOwner" /home/$whisparrOwner/.config

    echo_progress_start "Downloading release archive"
    case "$(_os_arch)" in
        "amd64") dlurl="http://whisparr.servarr.com/v1/update/nightly/updatefile?os=linux&runtime=netcore&arch=x64" ;;
        "armhf") dlurl="http://whisparr.servarr.com/v1/update/nightly/updatefile?os=linux&runtime=netcore&arch=arm" ;;
        "arm64") dlurl="http://whisparr.servarr.com/v1/update/nightly/updatefile?os=linux&runtime=netcore&arch=arm64" ;;
        *)
            echo_error "Arch not supported"
            exit 1
            ;;
    esac

    if ! curl "$dlurl" -L -o /tmp/Whisparr.tar.gz >> "$log" 2>&1; then
        echo_error "Download failed, exiting"
        exit 1
    fi
    echo_progress_done "Archive downloaded"

    echo_progress_start "Extracting archive"
    tar -xvf /tmp/Whisparr.tar.gz -C /opt >> "$log" 2>&1
    echo_progress_done "Archive extracted"

    touch /install/.whisparr.lock

    echo_progress_start "Installing Systemd service"
    cat > /etc/systemd/system/whisparr.service << EOF
[Unit]
Description=Whisparr Daemon
After=syslog.target network.target

[Service]
# Change the user and group variables here.
User=${whisparrOwner}
Group=${whisparrOwner}

Type=simple

# Change the path to Whisparr here if it is in a different location for you.
ExecStart=/opt/Whisparr/Whisparr -nobrowser -data=/home/$whisparrOwner/.config/Whisparr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

# These lines optionally isolate (sandbox) Whisparr from the rest of the system.
# Make sure to add any paths it might use to the list below (space-separated).
#ReadWritePaths=/opt/Whisparr /path/to/movies/folder
#ProtectSystem=strict
#PrivateDevices=true
#ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
    chown -R "$whisparrOwner":"$whisparrOwner" /opt/Whisparr
    systemctl -q daemon-reload
    systemctl enable --now -q whisparr
    sleep 1
    echo_progress_done "Whisparr service installed and enabled"

    if [[ -f $whisparrConfDir/update_required ]]; then
        echo_progress_start "Whisparr is installing an internal upgrade..."
        # echo "You can track the update by running \`systemctl status whisparr\`0. in another shell."
        # echo "In case of errors, please press CTRL+C and run \`box remove whisparr\` in this shell and check in with us in the Discord"
        while [[ -f $whisparrConfDir/update_required ]]; do
            sleep 1
            echo_log_only "Upgrade file is still here"
        done
        echo_progress_done "Upgrade finished"
    fi

}

_nginx_whisparr() {
    if [[ -f /install/.nginx.lock ]]; then
        echo_progress_start "Installing nginx configuration"
        #TODO what is this sleep here for? See if this can be fixed by doing a check for whatever it needs to
        sleep 10
        bash /usr/local/bin/swizzin/nginx/whisparr.sh
        systemctl -q reload nginx
        echo_progress_done "Nginx configured"
    else
        echo_info "Whisparr will be available on port 6969. Secure your installation manually through the web interface."
    fi
}

if [[ -z $whisparrOwner ]]; then
    whisparrOwner=$(_get_master_username)
fi

_install_whisparr
_nginx_whisparr

if [[ -f /install/.ombi.lock ]]; then
    echo_info "Please adjust your Ombi setup accordingly"
fi

if [[ -f /install/.tautulli.lock ]]; then
    echo_info "Please adjust your Tautulli setup accordingly"
fi

if [[ -f /install/.bazarr.lock ]]; then
    echo_info "Please adjust your Bazarr setup accordingly"
fi

echo_success "Whisparr installed"
