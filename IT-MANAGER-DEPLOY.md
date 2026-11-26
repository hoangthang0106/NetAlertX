# IT-MANAGER — NetAlertX cài qua Portainer / Docker

## 1. Quy ước cổng (theo yêu cầu)

- **Chỉ một cổng host cho NetAlertX: `18894:18894/tcp`**. Số cổng ngoài và trong container giống nhau.
- Truy cập sau khi deploy: **http://192.168.20.194:18894/** (nếu đây là IP của Docker host cài Stack).
- `18897` là cổng đã được báo trống nhưng **không dùng** cho NetAlertX lần này.
- Quy ước mặc định cho phần mềm tương lai: `PORT:PORT`, chọn một cổng chưa dùng trên cùng Docker host; không tự thêm cổng web thứ hai.
- API NetAlertX ở `20212` **chỉ chạy nội bộ trong container**, không được publish ra Docker host; giao diện web truy cập qua `/server` cùng cổng 18894.
- Socket proxy Docker (nếu sử dụng) chỉ `expose: 2375` trên mạng container, **không publish host port 2375**.

## 2. Triển khai Portainer Git Stack

Portainer → Stacks → Add Stack → Repository:

- Repository URL: `https://github.com/hoangthang0106/NetAlertX`
- Reference: `refs/heads/main`
- Compose path: `docker-compose.yml`
- Giữ tên stack cũ nếu đã triển khai và cần giữ nguyên named volume `/data`.
- Không cần nhập các biến Proxmox/Grafana vào Stack mặc định này.

Trong `docker-compose.yml` đã chỉnh:

```yaml
services:
  netalertx:
    ports:
      - "18894:18894/tcp"
    environment:
      LISTEN_ADDR: "0.0.0.0"
      PORT: "18894"
      GRAPHQL_PORT: "20212"
```

NetAlertX dùng bridge networking để Docker publish `18894:18894`; **ARP/NBNS/mDNS quét LAN có thể thiếu dữ liệu**, vì upstream khuyến nghị host networking cho L2. Khi cần quét đầy đủ L2 phải xem lại kiến trúc quét/collector, không thể khẳng định bridge tương đương host.

## 3. Kiểm tra cổng thật trên host

Chạy trên **chính** VM/LXC/Docker host sẽ deploy:

```bash
ss -lntp | grep ':18894 ' || true
docker ps --format 'table {{.Names}}\t{{.Ports}}'
# hoặc từ repo:
bash scripts/check-itmanager-ports.sh
```

Nếu đã có listener ở TCP/18894 thì **không deploy đè**; script chỉ kiểm tra và không thay đổi service. Mày đã báo 18894 và 18897 trống, nhưng đó không phải phép đo runtime từ phía tao.

## 4. Dữ liệu và Docker discovery

- NetAlertX dùng named volume `netalertx_data:/data` để giữ cấu hình, thiết bị, lịch sử sự kiện khi recreate; đừng chạy `docker compose down -v` và đừng xóa volume.
- Docker Socket Proxy (service `docker-socket-proxy`) có thể được NetAlertX DOCKERDISC gọi nội bộ qua `http://docker-socket-proxy:2375`, không cần thêm host port.
- Bật DOCKERDISC trong Settings và liên kết Docker host với device phù hợp; NetAlertX không tự sao lưu toàn bộ Docker volumes hoặc VM Proxmox.
- Proxy Docker cung cấp quyền đọc container Docker nhạy cảm, dù `POST=0`; chỉ dùng trên host tin cậy.
- Muốn lưu CPU/RAM/VM/LXC Proxmox dài hạn cần exporter/Prometheus (đã lưu riêng tại `compose-monitoring-optional.yml`); **không mặc định bật** vì yêu cầu lần này chỉ một host port.

## 5. Kiểm tra và sao lưu

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
docker logs netalertx --tail 100
curl -I http://192.168.20.194:18894/
sudo bash scripts/backup-itmanager.sh /opt/it-manager/backups
```

Đường dẫn mặc định sau deploy: http://192.168.20.194:18894. Không công bố cổng GraphQL hoặc Docker socket ra Internet.
