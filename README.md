# ĐỀ TÀI 3: TRIỂN KHAI WEBSITE QUẢNG BÁ SẢN PHẨM (WORDPRESS)

**Học phần:** Triển khai và Quản trị Hệ thống Phần mềm  
**Sinh viên thực hiện:** Nguyễn Khánh Duy  
**Mã sinh viên:** DTC245010053  
**Lớp:** KTMT K23A  
**Giảng viên hướng dẫn:** Hoàng Văn Tâm  

---

## 1. Tổng quan kiến trúc hệ thống

Hệ thống được triển khai hoàn toàn bằng **Docker Compose** gồm **12 container**, **6 Named Volumes** và được phân tách vào **3 mạng Docker độc lập** (tuân thủ hệ thống lý thuyết và thực hành từ Chương 1 đến Chương 9, đáp ứng đầy đủ 7 tiêu chí đánh giá):

- **`frontend` (Bridge):** Tiếp nhận lưu lượng người dùng qua `nginx` và kết nối với tầng ứng dụng (`wordpress`, `phpmyadmin`).
- **`backend` (Internal Bridge - `internal: true`):** Cô lập hoàn toàn cơ sở dữ liệu `mysql` khỏi mạng ngoài; chỉ cho phép `wordpress`, `phpmyadmin` và `mysql-exporter` giao tiếp nội bộ.
- **`monitoring` (Bridge):** Mạng dành riêng cho hệ thống giám sát (`prometheus`, `grafana`, `cadvisor`, `node-exporter`, `nginx-exporter`, `mysql-exporter`) và hệ thống thu thập log tập trung (`loki`, `promtail`).

### 1.1. Danh sách 12 dịch vụ & Cổng truy cập

| Dịch vụ (`service`) | Container Name | Image | Cổng (Host:Container) | Mạng tham gia | Vai trò |
| :--- | :--- | :--- | :---: | :--- | :--- |
| `nginx` | `nginx` | `nginx:alpine` | `80:80`, `443:443` | `frontend`, `monitoring` | Reverse Proxy (Single Entry Point), SSL/TLS tự ký, Security Headers |
| `wordpress` | `wordpress` | `wordpress:latest` | *(Nội bộ 80)* | `frontend`, `backend` | Website quảng bá sản phẩm |
| `mysql` | `mysql` | `mysql:8.0` | *(Nội bộ 3306)* | `backend` (`internal`) | Cơ sở dữ liệu chính |
| `phpmyadmin` | `phpmyadmin` | `phpmyadmin:latest` | `8080:80` | `frontend`, `backend` | Công cụ quản trị MySQL qua giao diện Web |
| `prometheus` | `prometheus` | `prom/prometheus:latest` | `9090:9090` | `monitoring` | Thu thập và lưu trữ metrics chuỗi thời gian (Pull model) |
| `grafana` | `grafana` | `grafana/grafana:latest` | `3000:3000` | `monitoring` | Trực quan hóa Dashboard & truy vấn LogQL |
| `cadvisor` | `cadvisor` | `gcr.io/cadvisor/cadvisor:v0.49.1` | *(Nội bộ 8080)* | `monitoring` | Thu thập metrics tài nguyên Container qua cgroup & Docker socket |
| `node-exporter` | `node-exporter` | `prom/node-exporter:latest` | *(Nội bộ 9100)* | `monitoring` | Thu thập metrics tài nguyên máy chủ Host |
| `nginx-exporter` | `nginx-exporter` | `nginx/nginx-prometheus-exporter:latest` | *(Nội bộ 9113)* | `monitoring` | Xuất metrics từ endpoint `/nginx_status` |
| `mysql-exporter` | `mysql-exporter` | `prom/mysqld-exporter:latest` | *(Nội bộ 9104)* | `backend`, `monitoring` | Xuất metrics hiệu năng MySQL (Multi-network attachment) |
| `loki` | `loki` | `grafana/loki:latest` | `3100:3100` | `monitoring` | Hệ thống lưu trữ và truy vấn log tập trung (TSDB v13) |
| `promtail` | `promtail` | `grafana/promtail:latest` | *(Nội bộ 9080)* | `monitoring` | Agent thu thập log từ Docker socket & Nginx volume |

### 1.2. Danh sách 6 Named Volumes lưu trữ bền vững (Chương 2 & Chương 3)

| Tên Volume | Container gắn kết | Đường dẫn trong Container | Mục đích lưu trữ bền vững |
| :--- | :--- | :--- | :--- |
| `mysql_data` | `mysql` | `/var/lib/mysql` | Bảo toàn dữ liệu cơ sở dữ liệu `wordpress_db` khi xóa/tạo lại container |
| `wordpress_data` | `wordpress` | `/var/www/html` | Lưu mã nguồn, cấu hình, theme, plugin và hình ảnh sản phẩm tải lên |
| `nginx_logs` | `nginx`, `promtail` | `/var/log/nginx` | Chia sẻ log truy cập/lỗi của Nginx sang `promtail` ở chế độ chỉ đọc (`:ro`) |
| `prometheus_data` | `prometheus` | `/prometheus` | Lưu trữ dữ liệu chuỗi thời gian (TSDB) của các chỉ số hệ thống |
| `grafana_data` | `grafana` | `/var/lib/grafana` | Lưu cấu hình người dùng và các Dashboard đã import trên Grafana |
| `loki_data` | `loki` | `/loki` | Lưu trữ các khối chỉ mục (index) và dữ liệu log tập trung (chunks) |

---

## 2. Cấu trúc thư mục dự án

```text
DTC245010053_DE3/
├── docker-compose.yml                                  # Khai báo 12 dịch vụ, 3 mạng, 6 named volumes
├── .env.example                                        # File mẫu biến môi trường
├── .gitignore                                          # Loại trừ file .env nhạy cảm khỏi Git
├── README.md                                           # Tài liệu hướng dẫn cài đặt, vận hành và demo
├── mysql/
│   └── init.sql                                        # Cấp quyền đọc metrics (PROCESS, REPLICATION CLIENT, SELECT) cho user giám sát
├── nginx/
│   ├── default.conf                                    # Cấu hình Reverse Proxy, HTTPS, Security Headers, /nginx_status
│   └── certs/                                          # Chứng chỉ SSL tự ký (selfsigned.crt, selfsigned.key)
├── prometheus/
│   ├── prometheus.yml                                  # Cấu hình 5 jobs thu thập metrics
│   └── .my.cnf                                         # Thông tin xác thực kết nối cho MySQL Exporter
├── grafana/
│   └── provisioning/datasources/datasources.yml        # Tự động nạp Datasource Prometheus & Loki
├── loki/
│   └── loki-config.yml                                 # Cấu hình Loki server (TSDB schema v13, retention 168h)
└── promtail/
    └── promtail-config.yml                             # Cấu hình Promtail thu thập log Docker & Nginx
```

---

## 3. Hướng dẫn cài đặt và vận hành hệ thống

### Bước 1: Clone repository về máy (Chương 4)
```bash
git clone https://github.com/duyduyduy6868/DTC245010053_DE3.git
cd DTC245010053_DE3
```

### Bước 2: Tạo file biến môi trường `.env` (Chương 3)
Sao chép từ file mẫu `.env.example`:
```bash
cp .env.example .env
```
*(Trên Windows PowerShell: `Copy-Item .env.example .env`)*

### Bước 3: (Tùy chọn) Tạo chứng chỉ SSL tự ký bằng OpenSSL (Chương 1)
Thư mục `nginx/certs/` đã có sẵn chứng chỉ mẫu phục vụ chạy thử nghiệm. Nếu muốn tự sinh mới:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/certs/selfsigned.key \
  -out nginx/certs/selfsigned.crt \
  -subj "/C=VN/ST=ThaiNguyen/L=ThaiNguyen/O=DTC245010053/CN=localhost"
```

### Bước 4: Khởi chạy và quản trị vòng đời bằng Docker Compose (Chương 3)
```bash
# Kiểm tra cú pháp file docker-compose.yml trước khi chạy
docker compose config

# Khởi chạy toàn bộ 12 dịch vụ ở chế độ chạy ngầm (Detached mode)
docker compose up -d

# Kiểm tra trạng thái hoạt động của 12 container
docker compose ps
```

**Các lệnh vận hành & kiểm tra thường dùng (Bảng 3.1 – 3.8 Chương 3):**
```bash
# Xem log theo thời gian thực của một dịch vụ cụ thể (ví dụ: wordpress hoặc mysql)
docker compose logs -f --tail=50 wordpress

# Kiểm tra các tiến trình đang chạy bên trong các container
docker compose top

# Khởi động lại toàn bộ dịch vụ hoặc một dịch vụ cụ thể
docker compose restart nginx

# Dừng và xóa các container (vẫn bảo toàn dữ liệu trong 6 Named Volumes)
docker compose down
```

---

## 4. Hướng dẫn truy cập & Demo các thành phần

### 4.1. Website WordPress & Nginx Reverse Proxy (Yêu cầu 2 & 3 - Chương 1, 3, 5, 6)
- **Website (HTTPS):** Truy cập `https://localhost` (hoặc `https://192.168.154.129`).
- **Tự động chuyển hướng HTTP -> HTTPS:** Truy cập `http://localhost` tự động trả về mã `301 Moved Permanently` sang `https://localhost`.
- **Kiểm tra Security Headers bằng lệnh `curl`:**
  ```bash
  curl -I http://localhost
  curl -kI https://localhost
  ```
- **Quản trị CSDL phpMyAdmin:** Truy cập `http://localhost:8080`
  - Tài khoản: `wp_user`
  - Mật khẩu: `WpUser@SecPass#2026!` (trong `.env`)

### 4.2. Hệ thống giám sát Prometheus + Grafana (Yêu cầu 4 - Chương 7)
- **Prometheus:** Truy cập `http://localhost:9090/targets` để kiểm tra trạng thái **UP (1/1)** của 5 job chuẩn theo tài liệu Chương 7:
  - `prometheus` (`localhost:9090`)
  - `node-exporter` (`node-exporter:9100`)
  - `cadvisor` (`cadvisor:8080`)
  - `nginx` (`nginx-exporter:9113`)
  - `mysql` (`mysql-exporter:9104`)
- **Grafana:** Truy cập `http://localhost:3000`
  - Tài khoản: `admin`
  - Mật khẩu: `Grafana@Pass#2026!`
  - Datasource **Prometheus** (`http://prometheus:9090`) và **Loki** (`http://loki:3100`) đã được cấu hình tự động (Provisioning).
  - Import Dashboard theo Bảng 7.3 tài liệu Chương 7 (`Dashboards -> New -> Import`):
    - **Node Exporter (Host):** ID **`1860`**
    - **cAdvisor / Docker Containers:** ID **`14282`** (hoặc **`193`**)
    - **Nginx Web Server:** ID **`12708`** (hoặc **`12740`** theo Chương 7)
    - **MySQL Database:** ID **`7362`** (hoặc **`11375`**)
  - *Lưu ý kỹ thuật khi triển khai trên Ubuntu 24.04 / 26.04 (nhân Linux dùng cgroup v2):*
    - Với Dashboard `14282`, sử dụng bộ lọc `{id=~"/system.slice/docker.*"}` để hiển thị đầy đủ thông số CPU/RAM/Network theo cgroup v2.
    - Với Dashboard `7362`, ô *Buffer Pool Size of Total RAM* sử dụng công thức `(mysql_global_variables_innodb_buffer_pool_size{instance="$host"} * 100) / scalar(node_memory_MemTotal_bytes)` do `mysql-exporter` và `node-exporter` tách biệt thành 2 container khác nhau.

### 4.3. Hệ thống Log tập trung Loki + Promtail & Truy vấn LogQL (Yêu cầu 5 - Chương 8)
- **Kiến trúc lưu trữ:** Loki sử dụng cơ chế lưu trữ **TSDB (`schema: v13`)** với chính sách lưu giữ log tự động `retention_period: 168h` (7 ngày). Promtail tự động phát hiện toàn bộ 12 container qua `/var/run/docker.sock` và gắn nhãn `container`, `service` (đồng thời hỗ trợ mở rộng sang Grafana Alloy và tích hợp cảnh báo Grafana Alerting / Alertmanager theo Chương 8).
- Truy cập **Grafana** (`http://localhost:3000`) -> menu **Explore** -> chọn nguồn dữ liệu **Loki** và chạy các câu truy vấn **LogQL** (theo đúng Bảng 8.1 & 8.2 tài liệu Chương 8):

1. **Query 1 - Xem toàn bộ log của Nginx hoặc WordPress:**
   ```logql
   {container="nginx"}
   ```
   hoặc:
   ```logql
   {container="wordpress"}
   ```
2. **Query 2 - Lọc các hành vi đăng nhập / POST request vào WordPress:**
   ```logql
   {container="wordpress"} |= "POST"
   ```
3. **Query 3 - Tìm kiếm lỗi và cảnh báo trên MySQL (không phân biệt hoa thường):**
   ```logql
   {container="mysql"} |~ "(?i)error|warn"
   ```
4. **Query 4 - Truy vấn kết hợp lỗi hoặc mã 404 trên cả WordPress và Nginx:**
   ```logql
   {service=~"wordpress|nginx"} |= "404"
   ```
5. **Query 5 - Thống kê tốc độ dòng log theo từng dịch vụ trong mỗi phút (biểu đồ Time Series):**
   ```logql
   sum by (container) (rate({container=~".+"}[1m]))
   ```
   *(hoặc riêng cho Nginx: `sum(rate({container="nginx"}[1m]))`)*

---

## 5. Các biện pháp Bảo mật - Hardening hệ thống (Yêu cầu 6 - Chương 2, 5, 6, 9)

1. **Non-root Container (Chương 2):**
   - Chạy tiến trình với user không phải root (`user:` directive) cho `mysql` (`999:999`), `prometheus` (`65534:65534`), `nginx-exporter` (`65534:65534`), `mysql-exporter` (`65534:65534`), `grafana` (`472:472`), `loki` (`10001:10001`).
2. **Network Isolation - Cô lập mạng 3 lớp (Chương 2, 7 & 9):**
   - Tách thành 3 mạng `frontend`, `backend` và `monitoring`.
   - Mạng `backend` cấu hình `internal: true` (chặn hoàn toàn kết nối trực tiếp ra/vào từ mạng bên ngoài).
   - Container `mysql` chỉ nằm trong `backend` và **không mở cổng `3306` ra máy host** (khắc phục triệt để rủi ro lộ cổng 3306 nêu tại Case Study Chương 9).
   - Container `wordpress` không mở cổng trực tiếp ra host, bắt buộc mọi lưu lượng đi qua Single Entry Point là `nginx` (Chương 5).
   - Khi vận hành thực tế trên máy chủ, các cổng quản trị (`8080`, `9090`, `3000`, `3100`) có thể giới hạn chỉ lắng nghe trên giao diện loopback `127.0.0.1` (`127.0.0.1:8080:80`, v.v.).
3. **Chống leo thang đặc quyền (`no-new-privileges`) & Read-Only Mounts (`:ro` - Chương 2):**
   - Khai báo `security_opt: - no-new-privileges:true` cho các dịch vụ ứng dụng, cơ sở dữ liệu và giám sát.
   - Gắn toàn bộ file cấu hình (`default.conf`, `certs`, `prometheus.yml`, `.my.cnf`, `loki-config.yml`, `promtail-config.yml`, `datasources.yml`, `init.sql`) ở chế độ chỉ đọc (`:ro`).
4. **Mật khẩu mạnh & Bảo vệ biến môi trường (`.env` + `.gitignore` - Chương 3 & 4):**
   - Sử dụng mật khẩu phức tạp (chữ hoa, chữ thường, số, ký tự đặc biệt), nạp qua `env_file: - .env` và loại trừ `.env` khỏi Git.
5. **Nguyên tắc Đặc quyền tối thiểu (PoLP - Chương 6) & Củng cố WordPress:**
   - Ứng dụng WordPress và phpMyAdmin chỉ dùng tài khoản `wp_user` (xác thực `caching_sha2_password` trên MySQL 8.0), tuyệt đối không dùng `root`.
   - Tắt chỉnh sửa mã nguồn theme/plugin trong trang quản trị (`define('DISALLOW_FILE_EDIT', true);`) và chặn truy cập `/xmlrpc.php`, file ẩn (`.env`, `.git`, `.htaccess`) trên Nginx.
6. **HTTPS/TLS & Security Headers trên Nginx (Chương 1 & 5):**
   - Chỉ cho phép giao thức `TLSv1.2` và `TLSv1.3`, bộ mã hóa `HIGH:!aNULL:!MD5`, ẩn phiên bản máy chủ (`server_tokens off;`).
   - Bổ sung 6 Security Headers: `Strict-Transport-Security`, `X-Frame-Options`, `X-XSS-Protection`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`.
7. **Kết hợp củng cố bảo mật tầng Máy chủ Host Linux (Chương 9):**
   - Thiết lập tường lửa **iptables / nftables** với chính sách mặc định `DROP` chuỗi `INPUT` và `FORWARD`, cho phép giao diện `lo`, các kết nối `ESTABLISHED,RELATED`, chỉ mở cổng `80`, `443`, `SSH` và giới hạn tốc độ gói tin chống tấn công SYN Flood / ICMP Flood.
   - Củng cố dịch vụ **SSH** (`/etc/ssh/sshd_config`: vô hiệu hóa đăng nhập root `PermitRootLogin no`, vô hiệu hóa mật khẩu `PasswordAuthentication no`, xác thực bằng khóa công khai chuẩn **Ed25519**) kết hợp công cụ chống tấn công Brute-force tự động (**Fail2Ban / CrowdSec**).

### Các câu lệnh kiểm chứng Hardening thực tế (Verification Commands)
```bash
# 1. Kiểm tra tiến trình chạy dưới quyền Non-root và cấu hình no-new-privileges
docker exec mysql id
docker exec prometheus id
docker inspect mysql --format '{{.HostConfig.SecurityOpt}}'

# 2. Kiểm tra thuộc tính cô lập mạng backend (Internal: true)
docker network inspect dtc245010053_de3_backend --format 'Network: {{.Name}} | Internal: {{json .Internal}}'

# 3. Kiểm tra danh sách cổng lắng nghe trên máy chủ (xác nhận không lộ cổng 3306)
sudo ss -tulnp | grep -E '80|443|3000|3100|8080|9090|3306'

# 4. Kiểm tra phân quyền tối thiểu (PoLP) của các tài khoản trong MySQL
docker exec mysql mysql -u root -p'Root@StrongPass#2026!' -e "SELECT user, host, plugin FROM mysql.user WHERE user IN ('root','wp_user'); SHOW GRANTS FOR 'wp_user'@'%';"
```

---

## 6. Lịch sử 03 mốc Commit theo quy định đề bài

- **Commit 1:** Triển khai WordPress, MySQL, phpMyAdmin và Nginx Reverse Proxy có HTTPS + Security Headers.
- **Commit 2:** Tích hợp Prometheus, Grafana, cAdvisor, Node Exporter, Nginx Exporter và MySQL Exporter.
- **Commit 3:** Triển khai Loki + Promtail thu thập log tập trung, hoàn thiện Hardening và README.
