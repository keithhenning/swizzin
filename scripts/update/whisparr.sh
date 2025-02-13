#!/bin/bash
if [[ -f /install/.whisparr.lock ]]; then
    #shellcheck source=sources/functions/utils
    . /etc/swizzin/sources/functions/whisparr

    #Move whisparr installs to v3.net
    if grep -q "ExecStart=/usr/bin/mono" /etc/systemd/system/whisparr.service; then
        echo_info "Moving Whisparr from mono to .Net"
        #shellcheck source=sources/functions/utils
        . /etc/swizzin/sources/functions/utils
        [[ -z $whisparrOwner ]] && whisparrOwner=$(_get_master_username)

        if [[ $(_whisparr_version) = "mono-v3" ]]; then
            echo_progress_start "Downloading release files"
            urlbase="http://whisparr.servarr.com/v1/update/nightly/updatefile?os=linux&runtime=netcore&arch="
            case "$(_os_arch)" in
                "amd64") dlurl="${urlbase}&arch=x64" ;;
                "armhf") dlurl="${urlbase}&arch=arm" ;;
                "arm64") dlurl="${urlbase}&arch=arm64" ;;
                *)
                    echo_error "Arch not supported"
                    exit 1
                    ;;
            esac
            if ! curl "$dlurl" -L -o /tmp/whisparr.tar.gz >> "$log" 2>&1; then
                echo_error "Download failed, exiting"
                exit 1
            fi
            echo_progress_done "Release downloaded"

            isactive=$(systemctl is-active whisparr)
            echo_log_only "Whisparr was $isactive"
            [[ $isactive == "active" ]] && systemctl stop whisparr -q

            echo_progress_start "Removing old binaries"
            rm -rf /opt/Whisparr/
            echo_progress_done "Binaries removed"

            echo_progress_start "Extracting archive"
            tar -xvf /tmp/Whisparr.tar.gz -C /opt >> "$log" 2>&1
            chown -R "$whisparrOwner":"$whisparrOwner" /opt/Whisparr
            echo_progress_done "Archive extracted"

            echo_progress_start "Fixing Whisparr systemd service"
            # Watch out! If this sed runs, the updater will not trigger anymore. keep this at the bottom.
            sed -i "s|ExecStart=/usr/bin/mono /opt/Whisparr/Whisparr.exe|ExecStart=/opt/Whisparr/Whisparr|g" /etc/systemd/system/whisparr.service
            systemctl daemon-reload
            [[ $isactive == "active" ]] && systemctl start whisparr -q
            echo_progress_done "Service fixed and restarted"
            echo_success "Whisparr upgraded to .Net"

            if [[ -f /install/.nginx.lock ]]; then
                echo_progress_start "Upgrading nginx config for Whisparr"
                bash /etc/swizzin/scripts/nginx/whisparr.sh
                systemctl reload nginx -q
                echo_progress_done "Nginx conf for Whisparr upgraded"
            fi

        elif [[ $(_whisparr_version) = "mono-v2" ]]; then
            echo_warn "Whisparr v0.2 is EOL and not supported. Please upgrade your whisparr to v3. An attempt will be made to migrate to .Net core on the next \`box update\` run"
            echo_docs "applications/whisparr#migrating-to-v3-on-net-core"
        fi
    else
        echo_log_only "Whisparr's service is not pointing to mono"
    fi
    #Mandatory SSL Port change for Readarr
    #shellcheck source=sources/functions/utils
    . /etc/swizzin/sources/functions/utils
    app_name="whisparr"
    if [ -z "$whisparrOwner" ]; then
        if ! whisparrOwner="$(swizdb get $app_name/owner)"; then
            whisparrOwner=$(_get_master_username)
            ownerToSetInDB='True'
        fi
    else
        ownerToSetInDB='True'
    fi

    app_configfile="/home/$whisparrOwner/.config/Whisparr/config.xml"

    if [[ $ownerToSetInDB = 'True' ]]; then
        if [ -e "$app_configfile" ]; then
            echo_info "Setting ${app_name^} owner = $whisparrOwner in SwizDB"
            swizdb set "$app_name/owner" "$whisparrOwner"
        else
            echo_error "${app_name^} config file for whisparr owner does not exist in expected location.
We are checking for $app_configfile.
If the user here is incorrect, please run \`whisparrOwner=<user> box update\`.
${app_name^} updater is exiting, please try again later."
            exit 1
        fi
    else
        echo_log_only "Whisparr owner $whisparrOwner apparently did not need an update"
    fi

    if grep -q "<SslPort>6969" "$app_configfile"; then
        echo_progress_start "Changing Whisparr's default SSL port"
        sed -i 's|<SslPort>6969</SslPort>|<SslPort>6868</SslPort>|g' "$app_configfile"
        systemctl try-restart -q whisparr

        if grep -q "<EnableSsl>True" "$app_configfile"; then
            echo_info "Whisparr SSL port changed from 6969 to 6868 due to Readarr conflicts; please ensure to adjust your dependent systems in case they were using this port"
        fi
        echo_progress_done "Whisparr's default SSL port changed"
    else
        echo_log_only "Whisparr's ports are not on 6969"
    fi
    if [[ -f /install/.nginx.lock ]]; then
        # check for /feed/calendar auth bypass
        if grep -q "6868/whisparr" /etc/nginx/apps/whisparr.conf || ! grep -q "calendar" /etc/nginx/apps/whisparr.conf; then
            echo_progress_start "Upgrading nginx config for Whisparr"
            bash /etc/swizzin/scripts/nginx/whisparr.sh
            systemctl reload nginx -q
            echo_progress_done "nginx config for Whisparr upgraded"
        fi
    fi
fi
