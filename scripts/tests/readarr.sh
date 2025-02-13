#!/usr/bin/env bash

#shellcheck source=sources/functions/tests
. /etc/swizzin/sources/functions/tests

check_service "whisparr" || BAD=true
check_port_curl "6969" || BAD=true
check_nginx "whisparr" || BAD=true

evaluate_bad
