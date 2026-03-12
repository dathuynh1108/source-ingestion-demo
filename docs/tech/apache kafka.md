# TÀI LIỆU CÔNG NGHỆ: APACHE KAFKA
**Phụ trách:** Member 3  
**Hạng mục:** Kafka consumer setup &  config 

---

## 1. Công nghệ này là gì?
Apache Kafka là một nền tảng xử lý luồng sự kiện phân tán (Distributed Event Streaming Platform) mã nguồn mở. Khác với các Database truyền thống lưu trữ trạng thái hiện tại, Kafka lưu trữ "dòng thời gian" của các sự kiện (log-based) theo dạng append-only (chỉ ghi nối thêm vào cuối). 



## 2. Vai trò trong phần việc của Member 3
Mặc dù luồng Ingestion đẩy dữ liệu vào Kafka, nhưng Member 3 là người chịu trách nhiệm thiết lập Consumer (người tiêu thụ). 
Trong kiến trúc này, Kafka đóng vai trò là "Vùng đệm giảm sốc" (Buffer). Nó giữ an toàn cho các message (giao dịch nhập/xuất kho) trong Topic. Member 3 cấu hình ClickHouse kết nối vào Kafka để hút dữ liệu ra theo tốc độ mà ClickHouse có thể xử lý, đảm bảo luồng Ingestion không làm rơi rớt dữ liệu.

## 3. Dùng khi nào?
* Khi cần kết nối (decouple) hệ thống sản xuất dữ liệu (Logstash/SQL Server) và hệ thống tiêu thụ dữ liệu (ClickHouse) có tốc độ xử lý khác nhau.
* Khi hệ thống yêu cầu thông lượng (throughput) cực cao, lên tới hàng triệu sự kiện giao dịch kho mỗi giây.
* Khi cần tính năng lưu vết (retention) để có thể đọc lại dữ liệu trong trường hợp Database đích bị sập.

## 4. So sánh với các công nghệ tương đương

### 4.1. Kafka vs. RabbitMQ (Message Broker truyền thống)
* **RabbitMQ:** Khi Consumer (ClickHouse) đọc xong 1 tin nhắn, RabbitMQ sẽ xóa tin nhắn đó. Rất khó để đọc lại (replay) nếu quá trình Ingestion xảy ra lỗi.
* **Kafka:** Lưu tin nhắn trên ổ cứng theo thời gian cấu hình. Nếu ClickHouse của Member 3 cấu hình sai hoặc bị sập, hệ thống hoàn toàn có thể tua lại (rewind offset) để ClickHouse đọc lại dữ liệu từ hôm qua mà không bị mất mát.

### 4.2. Kafka KRaft vs. Kafka Zookeeper (Phiên bản cũ)
* **Zookeeper:** Là công cụ quản lý cụm Kafka ở các bản cũ, làm kiến trúc bị cồng kềnh vì phải duy trì 2 service độc lập.
* **Kafka KRaft:** Phiên bản hiện đại (image `apache/kafka:4.1.1`) đã loại bỏ hoàn toàn Zookeeper. Metadata được quản lý trực tiếp bên trong Kafka Broker, giúp khởi động nhanh hơn, tiết kiệm RAM và dễ cấu hình trên Docker hơn rất nhiều.