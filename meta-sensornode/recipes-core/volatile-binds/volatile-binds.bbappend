# Không có cron, mail hay file server nên /var/spool và /srv không cần ghi được.
VOLATILE_BINDS = "\
    /var/volatile/lib /var/lib\n\
    /var/volatile/cache /var/cache\n\
"
