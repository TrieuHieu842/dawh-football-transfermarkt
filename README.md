# DAWH Football Transfermarkt

## 1. Giới thiệu

Đây là đồ án môn **Data Warehouse**, xây dựng kho dữ liệu phân tích bóng đá dựa trên dữ liệu từ **Transfermarkt**.

Đề tài áp dụng phương pháp **Kimball Dimensional Modeling** để thiết kế Data Warehouse theo mô hình **Fact Constellation (Galaxy Schema)**.

Mục tiêu của hệ thống là tích hợp dữ liệu bóng đá từ nhiều bảng dữ liệu nguồn và tổ chức lại thành các bảng Fact và Dimension, phục vụ cho việc phân tích đội bóng, cầu thủ, giá trị cầu thủ và hoạt động chuyển nhượng.

## 2. Nguồn dữ liệu

### Nguồn dữ liệu gốc

**Transfermarkt**

Website:

https://www.transfermarkt.com/

Transfermarkt là nguồn dữ liệu bóng đá được sử dụng để cung cấp thông tin về cầu thủ, câu lạc bộ, trận đấu, giá trị thị trường và chuyển nhượng.

### Dataset sử dụng trong đồ án

Đồ án sử dụng bộ dữ liệu:

**Transfermarkt Datasets**

Repository:

https://github.com/dcaribou/transfermarkt-datasets

Dataset được xây dựng từ dữ liệu Transfermarkt và cung cấp các bảng dữ liệu có thể liên kết với nhau thông qua các ID. Bộ dữ liệu bao gồm các thông tin về competitions, games, clubs, players, appearances, player valuations, club games, transfers và các bảng liên quan.

Tại thời điểm hiện tại, repository công bố dữ liệu với quy mô khoảng:

* 88,000+ trận đấu
* 50,000+ cầu thủ
* 1,890,000+ lượt cầu thủ xuất hiện trong trận đấu
* 650,000+ bản ghi lịch sử giá trị cầu thủ
* 175,000+ bản ghi chuyển nhượng
* 177,000+ bản ghi `club_games`
* 790+ câu lạc bộ
* 65 competitions

Các số liệu trên là quy mô được công bố trong dataset và có thể thay đổi tùy phiên bản dữ liệu được sử dụng. Repository hiện ghi nhận dữ liệu được cập nhật đến **06/07/2026** và quá trình cập nhật tự động đang tạm dừng.

## 3. Các bảng dữ liệu nguồn

Một số bảng dữ liệu chính được sử dụng:

| Bảng                | Nội dung                                    |
| ------------------- | ------------------------------------------- |
| `players`           | Thông tin cầu thủ                           |
| `clubs`             | Thông tin câu lạc bộ                        |
| `competitions`      | Giải đấu và các cuộc thi                    |
| `games`             | Thông tin trận đấu                          |
| `club_games`        | Thông tin trận đấu theo góc nhìn câu lạc bộ |
| `appearances`       | Thống kê cầu thủ trong từng trận            |
| `player_valuations` | Lịch sử giá trị thị trường của cầu thủ      |
| `transfers`         | Thông tin chuyển nhượng cầu thủ             |
| `countries`         | Thông tin quốc gia                          |
| `national_teams`    | Thông tin đội tuyển quốc gia                |

Dataset nguồn mô tả `appearances` là dữ liệu theo từng cầu thủ trong từng trận đấu, `player_valuations` lưu các bản ghi thay đổi giá trị cầu thủ và `transfers` lưu thông tin cầu thủ, câu lạc bộ đi, câu lạc bộ đến và phí chuyển nhượng.

## 4. Mục tiêu của Data Warehouse

Data Warehouse được xây dựng nhằm:

* Tích hợp dữ liệu bóng đá từ nhiều bảng dữ liệu nguồn.
* Chuẩn hóa dữ liệu phục vụ phân tích.
* Thiết kế mô hình dữ liệu theo phương pháp Kimball.
* Xây dựng các Dimension và Fact.
* Xử lý dữ liệu thay đổi theo thời gian bằng SCD.
* Hỗ trợ phân tích theo cầu thủ, câu lạc bộ, giải đấu, mùa giải và thời gian.
* Xây dựng dữ liệu tổng hợp phục vụ báo cáo và trực quan hóa.

## 5. Phạm vi phân tích

Đồ án tập trung vào 4 quy trình nghiệp vụ chính:

### 5.1. Hiệu suất đội bóng trong trận đấu

Phân tích:

* Số bàn thắng ghi được.
* Số bàn thua.
* Kết quả thắng, hòa, thua.
* Clean sheet.
* Vị trí của đội bóng.

### 5.2. Hiệu suất cầu thủ trong trận đấu

Phân tích:

* Số phút thi đấu.
* Bàn thắng.
* Kiến tạo.
* Thẻ vàng.
* Thẻ đỏ.
* Số lần ra sân.

### 5.3. Giá trị cầu thủ

Phân tích:

* Giá trị thị trường của cầu thủ.
* Biến động giá trị theo thời gian.
* Giá trị cầu thủ theo câu lạc bộ.
* Giá trị cầu thủ theo mùa giải.

### 5.4. Chuyển nhượng

Phân tích:

* Lịch sử chuyển nhượng.
* Câu lạc bộ đi và câu lạc bộ đến.
* Phí chuyển nhượng.
* Giá trị thị trường tại thời điểm chuyển nhượng.
* Chênh lệch giữa phí chuyển nhượng và giá trị thị trường.

## 6. Mô hình Data Warehouse

Kho dữ liệu được thiết kế theo **Fact Constellation / Galaxy Schema**, trong đó nhiều Fact sử dụng các Dimension dùng chung.

### Fact

* `Fact_Team_Match`
* `Fact_Player_Appearance`
* `Fact_Player_Valuation`
* `Fact_Transfer`

### Dimension

* `Dim_Date`
* `Dim_Club`
* `Dim_Player`
* `Dim_Season`
* `Dim_Competition`
* `Dim_Match`
* `Dim_Manager`
* `Dim_Transfer_Type`

Ngoài ra, hệ thống có các bảng tổng hợp:

* `Fact_Player_Season_Summary`
* `Fact_Club_Season_Summary`

## 7. Thiết kế ETL
Quy trình dữ liệu được tổ chức theo các lớp:
Transfermarkt Dataset
        |
        v
   Staging Raw
        |
        v
  Staging Clean
        |
        v
 Data Warehouse
        |
        v
 Aggregate Facts
        |
        v
 Reporting / BI
Các bước chính:
1. Extract dữ liệu từ các file CSV.
2. Load dữ liệu vào Staging.
3. Làm sạch và chuẩn hóa dữ liệu.
4. Kiểm tra chất lượng dữ liệu.
5. Load Dimension.
6. Load Fact.
7. Xử lý SCD đối với các Dimension có thay đổi.
8. Xây dựng các bảng tổng hợp.
9. Cung cấp dữ liệu cho hệ thống báo cáo và BI.
## 8. Công nghệ sử dụng
* Data Warehouse: Kimball Dimensional Modeling
* Database: SQL Server
* ETL: Python / SQL
* Data Source: Transfermarkt
* Dataset: Transfermarkt Datasets
* Visualization: Power BI


## 9. Tài liệu tham khảo và nguồn dữ liệu

1. Transfermarkt
   https://www.transfermarkt.com/

2. Transfermarkt Datasets - GitHub
   https://github.com/dcaribou/transfermarkt-datasets

3. Transfermarkt Datasets - Dataset Metadata
   https://github.com/dcaribou/transfermarkt-datasets/blob/master/data/prep/dataset-metadata.json

4. Kimball Group - Dimensional Modeling
   https://www.kimballgroup.com/

## 10. Lưu ý về dữ liệu

Dữ liệu được sử dụng cho mục đích học tập và xây dựng đồ án Data Warehouse.

Dữ liệu gốc có nguồn từ Transfermarkt và được cung cấp thông qua bộ Transfermarkt Datasets. Repository của dataset mô tả rõ nguồn dữ liệu, cấu trúc các bảng và quy trình thu thập/xử lý dữ liệu.
