# sensornode-webd chỉ phục vụ HTTP trong LAN, không cần HTTPS hay curl (bỏ kéo theo gnutls, libgcrypt).
PACKAGECONFIG:remove = "curl https"
