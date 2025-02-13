#!/bin/bash
systemctl disable --now -q whisparr
rm /etc/systemd/system/whisparr.service
systemctl daemon-reload -q
rm -rf /opt/Whisparr

if [[ -f /install/.nginx.lock ]]; then
    rm /etc/nginx/apps/whisparr.conf
    systemctl reload nginx
fi

rm /install/.whisparr.lock
