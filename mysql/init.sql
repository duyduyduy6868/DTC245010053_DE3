-- Cấp quyền đọc metrics hệ thống (PROCESS, REPLICATION CLIENT, SELECT) cho user giám sát
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'wp_user'@'%';
FLUSH PRIVILEGES;

