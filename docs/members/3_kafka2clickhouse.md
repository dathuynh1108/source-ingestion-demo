# HƯỚNG DẪN TRIỂN KHAI VÀ VẬN HÀNH: MEMBER 3

**Module:** Kafka & ClickHouse Ingestion Pipeline

**Mục tiêu:** Đảm bảo luồng dữ liệu chảy xuyên suốt từ Kafka Topic vào ClickHouse Raw Table, xử lý tự động và chịu lỗi tốt.

---

## 1. Biện luận lựa chọn Image (Tại sao là Apache Kafka Official?)

Trên thị trường có rất nhiều bản phân phối Kafka (Confluent, Bitnami, Wurstmeister). Tuy nhiên, đối với kiến trúc của dự án này, việc chọn **`apache/kafka:4.1.1`** (bản chính thức từ Apache) mang lại các lợi thế quyết định:

* **Không dư thừa (Lightweight):** Bản phân phối của Confluent rất mạnh nhưng đi kèm hệ sinh thái quá nặng (Schema Registry, REST Proxy...) không cần thiết cho phạm vi môn học.
* **Hỗ trợ KRaft Native:** Từ bản 3.x, Apache đã tập trung phát triển KRaft (loại bỏ Zookeeper). Việc dùng bản chính chủ 4.x đảm bảo tính ổn định cao nhất khi cấu hình KRaft thông qua các biến môi trường chuẩn.
* **Không bị bọc lớp ảo (No wrapper script):** Các bản như Bitnami thường có các đoạn script wrapper tùy biến riêng. Khi có lỗi khởi tạo, việc debug trên bản Apache gốc luôn dễ dàng và bám sát tài liệu chính thức (Documentations) nhất.

---

## 2. Giải thích kiến trúc cấu hình

Hệ thống được thiết lập thông qua hai file cốt lõi: `docker-compose.yml` (Hạ tầng) và `init_tables.sql` (Lược đồ dữ liệu).

### 2.1. Hạ tầng mạng và Container (`docker-compose.yml`)

* **Cơ chế Listeners Đa luồng (Kafka):** Cấu hình `EXTERNAL://0.0.0.0:29092` và `PLAINTEXT://0.0.0.0:9092` cho phép Kafka vừa phục vụ các container bên trong mạng ảo (ClickHouse), vừa mở cửa để các script giả lập (Golang/Python) từ máy tính Host bên ngoài bắn dữ liệu vào qua cổng `29092`.
* **Tự động hóa luồng khởi tạo (Init Container):**
Sử dụng `kafka-init` làm container phụ trợ. Container này sẽ chờ Kafka đạt trạng thái `healthy`, sau đó chạy script tạo sẵn topic `inventory_topic` rồi tự động tắt (`restart: "no"`). Nhờ đó, luồng dữ liệu không bao giờ bị nghẽn do thiếu Topic.
* **Bảo vệ Khởi động chéo (Dependency & Healthcheck):**
ClickHouse chỉ được phép khởi động khi `kafka-init` báo cáo `service_completed_successfully`. Điều này triệt tiêu hoàn toàn lỗi ClickHouse cố kết nối vào Kafka khi Topic chưa tồn tại.
* **Bảo mật ClickHouse:**
Biến môi trường được cấu hình cứng với User là `password` và Password là `admin`. (*Lưu ý: Tên user hiện đang đặt là "password", hãy sử dụng đúng thông tin này khi kết nối qua các database UI tools*).

### 2.2. Lược đồ Dữ liệu và Ingestion (`init_tables.sql`)

Kiến trúc sử dụng mô hình 3 bảng để "tiêu thụ" (consume) dữ liệu mà không cần viết code:

1. **Raw Table (`raw_inventory_transactions`):** * Bổ sung cơ chế `PARTITION BY toYYYYMM(event_time)`: Đây là một kỹ thuật tối ưu hóa truy vấn cực tốt cho dữ liệu chuỗi thời gian. Nó chia nhỏ dữ liệu vật lý theo từng tháng, giúp dbt sau này scan data nhanh hơn hàng chục lần.
2. **Kafka Engine Table (`kafka_inventory_consumer`):**
* `kafka_max_block_size = 1000` & `kafka_poll_timeout_ms = 1000`: Ép ClickHouse gom các tin nhắn nhỏ lẻ thành từng cụm (batch) tối đa 1000 dòng hoặc mỗi giây để ghi vào đĩa, tối ưu hóa I/O thay vì ghi lắt nhắt từng dòng.


3. **Materialized View (`inventory_mv`):**
Đóng vai trò là ống dẫn tự động, parse JSON từ bảng Engine và chèn cột `ingestion_time` tự động (System Timestamp) rồi đẩy xuống Raw Table.

---

## 3. Quy trình Vận hành Hệ thống (How to Run)

Để kiểm thử và chứng minh hệ thống hoạt động hoàn hảo, hãy thực hiện theo 4 bước sau:

**Bước 1: Khởi tạo toàn bộ kiến trúc**
Mở terminal tại thư mục chứa file `docker-compose.yml`, chạy lệnh:

```bash
docker-compose up -d
```

*Đợi khoảng 20-30 giây để các healthcheck chuyển sang trạng thái xanh.* Bạn có thể kiểm tra bằng lệnh `docker ps`.

**Bước 2: Xác nhận ClickHouse Schema tự động**
ClickHouse đã tự động mount thư mục `./clickhouse_init` và chạy file SQL.

* Mở database UI tool (hoặc Web UI: `http://localhost:8123/play`).
* Đăng nhập bằng thông tin đã cấu hình:
* Username: `password`
* Password: `admin`


* Chạy lệnh `SHOW TABLES;`. Nếu thấy 3 bảng `raw_inventory_transactions`, `kafka_inventory_consumer` và `inventory_mv` xuất hiện, quá trình init đã thành công.

**Bước 3: Giả lập dòng dữ liệu bằng Kafka UI**

* Truy cập `http://localhost:8080`.
* Vào mục **Topics** -> Chọn `inventory_topic` -> **Messages** -> **Produce Message**.
* Nhập chuỗi JSON sau vào ô *Value* và gửi (key là optional):

```json
{
  "warehouse_id": "WH_DAN_TRAN_01",
  "sku_id": "SKU_DAN_TRAN_PRODUCT",
  "qty_change": 15,
  "event_time": "2026-02-28 20:00:00"
}
```

**Bước 4: Kiểm chứng kết quả Ingestion**    
Quay lại trình quản lý ClickHouse, chạy câu lệnh truy vấn:

```sql
SELECT * FROM raw_inventory_transactions ORDER BY ingestion_time DESC LIMIT 1;
```

Nếu dòng dữ liệu hiển thị tức thì với thời gian hệ thống được ghi nhận chính xác ở cột `ingestion_time`, luồng Ingestion Kafka-ClickHouse đã được thiết lập thành công 100%. Member 4 (dbt) bắt đầu nối vào bảng Raw này.