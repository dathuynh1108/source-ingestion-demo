# TÀI LIỆU CÔNG NGHỆ: CLICKHOUSE
**Phụ trách:** Member 3     
**Hạng mục:** ClickHouse raw table, ClickHouse ingestion & ClickHouse DDL 

---

## 1. Công nghệ này là gì?
ClickHouse là một hệ quản trị cơ sở dữ liệu hướng cột (Column-oriented DBMS) mã nguồn mở, được tối ưu hóa cực đoan cho các tác vụ Phân tích Dữ liệu Trực tuyến (OLAP - Online Analytical Processing). 



## 2. Vai trò trong phần việc của Member 3
Đây là "vũ khí" chính của Member 3. Công nghệ này được sử dụng để giải quyết 2 nhiệm vụ cốt lõi:
1.  **Lưu trữ Raw Data:** Tạo bảng `raw_inventory_transactions` thông qua các câu lệnh DDL để làm kho chứa dữ liệu thô phục vụ việc show raw data lúc demo.
2.  **ClickHouse Ingestion:** Thay vì dùng script lập trình bên ngoài, Member 3 dùng chính tính năng **Kafka Table Engine** của ClickHouse để tự động kéo dữ liệu (ingest) từ Kafka vào bảng Raw.

## 3. Dùng khi nào?
* Khi cần lưu trữ dữ liệu sự kiện giao dịch siêu lớn (chuỗi thời gian của hàng hóa ra/vào kho).
* Khi cần chạy các câu lệnh SQL tổng hợp (như tính `SUM` tồn kho) trên hàng tỷ dòng dữ liệu và yêu cầu trả về kết quả trong vài mili-giây để Dashboard hiển thị ngay lập tức.

## 4. So sánh với các công nghệ tương đương

### 4.1. ClickHouse vs. SQL Server / PostgreSQL (OLTP)
* **SQL Server (Hệ thống nguồn):** Lưu dữ liệu theo dòng (Row-oriented). Để tính tổng một cột, nó phải đọc cả những cột không cần thiết từ ổ cứng lên RAM, dẫn đến thắt cổ chai I/O khi dữ liệu kho hàng phình to.
* **ClickHouse (Data Warehouse):** Lưu dữ liệu theo cột (Column-oriented). Khi hệ thống tính tổng số lượng (`qty_change`), nó chỉ bốc duy nhất file chứa cột đó trên đĩa ra tính toán. Tốc độ đọc đĩa giảm hàng chục lần, truy vấn phân tích siêu nhanh.

### 4.2. ClickHouse vs. Apache Cassandra (NoSQL)
* **Cassandra:** Là hệ thống NoSQL phân tán cực mạnh về Ghi (Write-heavy). Tuy nhiên, nó không hỗ trợ tốt các phép `JOIN` hay tính `GROUP BY`.
* **ClickHouse:** Vừa có tốc độ ghi dữ liệu khổng lồ (thông qua engine MergeTree), vừa giữ được sức mạnh truy vấn phân tích SQL chuẩn. Điều này giúp dbt (Member 4) dễ dàng Transform dữ liệu bằng SQL truyền thống.

### 4.3. ClickHouse Kafka Engine vs. Script Consumer (Python/Go)
* **Viết Code Consumer:** Lập trình viên phải tự quản lý việc commit offset, xử lý đa luồng, quản lý rớt mạng và tự viết lệnh `INSERT` vào DB. Rất dễ sinh bug.
* **ClickHouse Kafka Engine:** Pull dữ liệu trực tiếp bằng lõi C++ của Database, tự động quản lý offset với Kafka, và triển khai toàn bộ chỉ bằng câu lệnh SQL (DDL). Đây là cách tiếp cận hiện đại và tối ưu nhất cho Data Engineering.