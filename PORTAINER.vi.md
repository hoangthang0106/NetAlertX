# NetAlertX – cài trên Portainer bằng Git (IT-MANAGER)

Repository: https://github.com/hoangthang0106/NetAlertX

## 1. Cấu hình đã chuẩn bị

| Mục | Cấu hình |
|---|---|
| Stack / container | `netalertx` / `netalertx` |
| Số container | **1** |
| Image | `ghcr.io/netalertx/netalertx:latest` (image công bố chính thức, **không build từ fork**) |
| Nhánh | `main` |
| File | `docker-compose.yml` |
| Docker network | `host` để quét ARP trên đúng LAN của máy Docker |
| Web UI | **TCP 18897** (giữ chuẩn cổng ngoài/cổng tiến trình như nhau) |
| GraphQL/backend API | **TCP 18898**, một tiến trình khác nằm trong CÙNG container |
| Volume | `netalertx_data:/data`, giữ config và SQLite |
| Proxy, Caddy, database/container phụ | **Không có** |

**Tại sao không dùng `ports: 18897:18897`?**
Docker `network_mode: host` không sử dụng Docker port publishing; nginx chạy trực tiếp trên **host TCP 18897**, Flask/GraphQL API trực tiếp trên **host TCP 18898**. Dùng `ports:` cùng host mode là cấu hình sai/không có hiệu lực. NetAlertX có 2 listener, khác với app web 1 port.

**Trạng thái cũ**: Người dùng đã xóa SpiderFoot (`18894`) và PerkRadar (`18897`) khỏi Portainer. Lần này **tái sử dụng 18897 cho NetAlertX**. Port **18898** có trong fork Social Analyzer cũ (chưa xác minh có chạy); không deploy đồng thời. Trước khi bấm Deploy, phải xác minh 18897/18898 thực sự trống trên đúng Docker host.

## 2. Kiểm tra trước khi cài

Trên đúng VM/LXC/Linux Docker host, dùng lệnh chỉ đọc:

```sh
ip -br addr
ip route
ss -lntp '( sport = :18897 or sport = :18898 )'
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

- Đảm bảo **`LAN_IP` là IP của chính Linux Docker host**, ví dụ `192.168.20.194` nếu IP này vẫn thuộc VM/LXC. Chỉ cần IP, **không điền `http://` hay `:18897`**.
- Đảm bảo máy đang chạy Docker **Linux**. Trong Docker chạy bên trong LXC/VM/Proxmox, host network chỉ cho truy cập card mạng **của LXC/VM**, không tự lấy quyền vào NIC/VLAN của máy Proxmox.
- Nếu 18897 hoặc 18898 đã có tiến trình lắng nghe, **không triển khai** trước khi xử lý xung đột.

## 3. Portainer → Stacks → Add stack → Git repository

| Trường | Giá trị |
|---|---|
| Name | `netalertx` |
| Repository URL | `https://github.com/hoangthang0106/NetAlertX.git` |
| Repository reference | **`refs/heads/main`** |
| Compose path | **`docker-compose.yml`** |
| Authentication | None (fork công khai) |

Ở mục **Environment variables** thêm:

| Name | Value |
|---|---|
| `LAN_IP` | IP LAN thật của máy Docker, ví dụ `192.168.20.194` nếu IP hiện tại vẫn như vậy |

Không cần build image, không cần viết Dockerfile, không cần thêm `PORT` hoặc `GRAPHQL_PORT` trong Portainer vì Compose đã cố định **18897** và **18898**.

Kiểm tra tường lửa rồi nhấn **Deploy the stack**.

## 4. Bảo mật bắt buộc trước khi cho người khác truy cập

**CẢNH BÁO**: Theo mã nguồn NetAlertX, API Flask/GraphQL mặc định bind **`0.0.0.0:18898`**, không bị hạn chế bởi `LISTEN_ADDR` của Web UI. Vì dùng `host` network, **API 18898 thực sự mở trên IP host**, không chỉ ở trong Docker. Cần **firewall trên Linux Docker host hoặc firewall trước host** để chặn 18898 từ LAN không tin cậy/Internet; không forward port 18897 hay 18898 qua router.

Với host hỗ trợ UFW, có thể cấu hình chính sách chỉ cho cổng UI truy cập từ các IP/VLAN quản trị được phép và **deny TCP 18898 từ mạng ngoài host**, nhưng **kiểm tra chính sách hiện hành trước khi dùng UFW**. Nếu host là VM/LXC sau Proxmox, có thể sử dụng firewall Linux hoặc Proxmox VM/CT firewall theo chính sách hệ thống. Không thay đổi firewall theo hướng làm mất kết nối SSH/Portainer.

**Web UI không bắt buộc đăng nhập theo mặc định.** Ngay khi mở lần đầu, vào **Settings → Set Password**, đổi mật khẩu mặc định `123456` thành mật khẩu mạnh và bật **Enable login**. Kiểm tra mở tab ẩn danh có yêu cầu mật khẩu. Không mở rộng quyền xem giao diện trước khi hoàn thành bước này. Mật khẩu/tokens **không ghi lên GitHub**.

Image dùng `cap_drop: ALL` và thêm lại đúng các capability NetAlertX upstream yêu cầu: `NET_ADMIN`, `NET_RAW`, `NET_BIND_SERVICE`, `CHOWN`, `SETUID`, `SETGID`. Không có `privileged: true`, không mount Docker socket, không tự thêm reverse proxy. Cấu hình `sysctls` host-network **được chủ động bỏ** để tránh thay đổi tham số kernel của host khi triển khai.

## 5. Sử dụng

- Mở **`http://LAN_IP:18897`** trên thiết bị quản trị cùng LAN.
- **Settings → Set Password** làm trước, rồi **Settings → ARPSCAN / SCAN_SUBNETS**.
- NetAlertX cần xác định **subnet và interface thật** để quét ARP. Ví dụ **chỉ khi đã xác nhận** mạng Docker host là `192.168.20.0/24` và card mạng thật `eth0` thì khai báo:

```text
SCAN_SUBNETS = ['192.168.20.0/24 --interface=eth0']
```

- Đọc `ip route` và `ip -br addr` để xác nhận interface/netmask, **không đoán** từ IP URL.
- Chạy quét trong phạm vi mạng được phép quản lý. ARPSCAN không tự phát hiện các thiết bị ở VLAN khác; mở rộng qua DHCP/SNMP, NMAPDEV hoặc Sync Node sau.
- Chờ lượt quét đầu hoàn tất, xem **Devices**, kiểm tra thiết bị lạ/new devices và cấu hình Alerts.

## 6. Kiểm tra lỗi

- Portainer → **Containers → netalertx → Logs**: kiểm tra khởi động services Nginx, Flask, ARPSCAN.
- Kiểm tra 18897 và 18898 bằng `ss -lntp` trên đúng Docker host; host network sẽ không hiển thị mapping `18897:18897` ở cột Published Ports của Portainer (bình thường).
- Web báo `connection refused`: kiểm tra `LAN_IP`/listener; cổng trùng, Nginx config writable.
- Web mở nhưng dữ liệu trống: kiểm tra `SCAN_SUBNETS`, `--interface`, `NET_RAW`/`NET_ADMIN`, quyền truy cập LAN. 
- `Operation not permitted`: với Docker trong LXC, kiểm tra quyền container LXC và kernel; **không tự bật privileged**.
- Portainer nói `reference not found`: dùng đúng nhánh **`refs/heads/main`**.
- Không xóa volume `netalertx_data` khi Update/Upgrade; backup `/data/config` và `/data/db`.
- Git Stack `Pull and redeploy` chỉ cập nhật Compose. Vì dùng upstream image `latest`, cần xác nhận rõ khi pull image mới; code fork thay đổi không tự được build vào image.

**Trạng thái: đã sửa Compose và thêm hướng dẫn trên GitHub. Chưa deploy lên Docker host và chưa xác minh cả hai cổng trống.**
