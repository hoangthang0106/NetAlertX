# IT-MANAGER: triển khai NetAlertX + Proxmox + Docker + lịch sử

## Mục đích
- NetAlertX: IP/MAC, trạng thái online/offline, nhật ký sự kiện thiết bị và Docker discovery.
- Proxmox: Prometheus PVE exporter lấy CPU/RAM/disk/storage/VM/LXC và các metric API PVE cho phép.
- Docker: Telegraf lấy metric theo container qua Docker Engine API.
- Prometheus: lưu lịch sử mặc định **730 ngày hoặc 60GB, giới hạn nào tới trước**.
- Grafana: tra cứu biểu đồ theo khung thời gian. Các volume Docker giữ dữ liệu khi restart/redeploy.

**Giới hạn:** không sao lưu ảnh đĩa VM, nội dung VM/LXC, Docker application volumes, toàn bộ file hay raw logs, không lấy được dữ liệu từ trước ngày cài, không tự thu thập các Docker engine trên VM/host khác.

## 1) Token Proxmox chỉ đọc
Trong shell Proxmox chạy:

~~~bash
pveum user add historian@pve --comment "IT-MANAGER metrics reader"
pveum aclmod / -user historian@pve -role PVEAuditor
pveum user token add historian@pve netalertx --privsep 0
~~~

Chép **giá trị token secret** vừa tạo vào nơi lưu bí mật; không commit lên GitHub. PVE_USER là historian@pve; PVE_TOKEN_NAME là netalertx. Máy Docker phải truy cập HTTPS TCP/8006 của Proxmox.

## 2) Cài bằng Portainer Git Stack (Docker Standalone trên Linux)
Portainer → Stacks → Add Stack → Repository:
- Repository: https://github.com/hoangthang0106/NetAlertX
- Reference: refs/heads/main
- Compose path: docker-compose.yml

Thêm biến môi trường trong phần Stack (các IP bên dưới là ví dụ, **không phải IP đã xác minh**):

| Biến môi trường | Ý nghĩa |
|---|---|
| LAN_IP | IP trên **chính Docker host** chạy stack, thí dụ 192.168.20.194 |
| PVE_HOST | IP/DNS node Proxmox; không thêm https:// hay :8006 |
| PVE_USER | historian@pve |
| PVE_TOKEN_NAME | netalertx |
| PVE_TOKEN_VALUE | Secret của Proxmox API token |
| PVE_VERIFY_SSL | true; chỉ đặt false với PVE self-signed nếu chấp nhận rủi ro |
| GRAFANA_ADMIN_USER | admin hoặc tên khác |
| GRAFANA_ADMIN_PASSWORD | Mật khẩu mạnh, dùng khi khởi tạo Grafana lần đầu |
| NETALERTX_API_TOKEN | Tùy chọn; để trống lúc cài đầu, sau đó cập nhật để lấy NetAlertX /metrics |
| METRICS_RETENTION | 730d (tùy chọn) |
| METRICS_MAX_SIZE | 60GB (tùy chọn) |

Bấm **Deploy the stack**.

NetAlertX web: http://LAN_IP:18897; API: TCP 18898 (host network, cần firewall hạn chế truy cập); Grafana: http://LAN_IP:18899; Prometheus chỉ publish 127.0.0.1:19090; socket proxy chỉ publish 127.0.0.1:2375. Không mở cổng API/metrics/2375 ra Internet.

## 3) Plugin Docker của NetAlertX
Vào NetAlertX → Settings → Docker discovery (DOCKERDISC), thêm một Docker host:
- Docker Socket Proxy URL: http://127.0.0.1:2375
- Docker Host MAC: MAC của Docker host nếu plugin không tự nhận diện bằng hostname.
- Host cần tồn tại như một device NetAlertX. Containers hiện tại sẽ nằm trong Device Details → Plugins → DOCKERDISC.

**Cảnh báo quan trọng:** dù POST=0, Tecnativa docker-socket-proxy với CONTAINERS=1 có thể cho phép GET đọc archive/export và file container. Chỉ dùng trên host tin cậy, **không mở 2375 ra LAN/WAN**, không cho container khác truy cập mạng proxy. Tham khảo https://github.com/Tecnativa/docker-socket-proxy/issues/182 . Với môi trường yêu cầu bảo mật cao, thay bằng proxy lọc whitelist endpoint nghiêm ngặt.

## 4) Truy xuất lịch sử
Grafana đã tự provision datasource **IT-MANAGER Prometheus**. Chọn Explore và thử PromQL:

~~~promql
up
up{job="proxmox"}
pve_up
pve_memory_usage_bytes
pve_disk_usage_bytes
up{job="docker"}
netalertx_connected_devices
~~~

Job netalertx chỉ xuất hiện khi NETALERTX_API_TOKEN được cung cấp; sau khi sửa biến môi trường cần redeploy để monitoring-init chạy lại. Job proxmox chỉ trỏ **1 PVE_HOST mặc định**; nếu có cluster nhiều node phải mở rộng target và chạy exporter cho mỗi node cần node-level metrics. Docker chỉ thu thập **engine nơi stack được cài**, không tự lấy mọi Docker host do Portainer quản lý.

Lệnh kiểm tra trên Docker host:
~~~bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker logs itmanager-pve-exporter --tail 100
docker logs itmanager-telegraf --tail 100
docker logs itmanager-prometheus --tail 100
~~~

Container monitoring-init ở trạng thái exited (0) là bình thường. Đừng dùng docker compose down -v, xóa volumes hay tạo Portainer Stack mới với tên khác khi đã có dữ liệu. Volume NetAlertX giữ tên theo project Compose gốc; các volume Prometheus và Grafana dùng tên cố định.

## 5) Backup
Trên **Docker host** chạy:
~~~bash
git clone https://github.com/hoangthang0106/NetAlertX.git
cd NetAlertX
sudo bash scripts/backup-itmanager.sh /opt/it-manager/backups
~~~

Script tạm dừng NetAlertX, Prometheus và Grafana để tạo archive nhất quán, sau đó khởi động lại các container trước đó đang chạy. Backup Prometheus có thể rất lớn và sẽ gây gián đoạn trong lúc sao lưu. Chuyển backup sang ổ/NAS **khác máy**, thử khôi phục định kỳ. Lưu bí mật Portainer stack environment riêng. Không nhầm backup metric với backup toàn bộ VM/LXC/container.
