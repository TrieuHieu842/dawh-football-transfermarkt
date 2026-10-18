# Context giai đoạn SSAS & Power BI – Phần 2

> Nội dung: **Hiệu suất cầu thủ + tổng hợp đối chiếu cube = SQL**. File này tự đủ thông tin; ai nhận phần này có thể dán nguyên vào trợ lý AI để làm tiếp.

## A. Bối cảnh dự án

- Đồ án môn Kho dữ liệu: **Football Transfermarkt DWH**, mô hình Kimball, **Galaxy Schema** (4 fact dùng chung dimension).
- Nguồn: bộ Kaggle / GitHub *transfermarkt-datasets* (10 file CSV).
- ETL bằng **SSIS** đã xong (`etl-ssis-transfermarkt/.../Main_ETL_Master.dtsx`). Kho `football_dwh_dw` trên SQL Server 2022 đã nạp đủ và qua kiểm tra (`sql/99_kiem_tra_ket_qua.sql`).
- Nguyên tắc thầy đã duyệt:
  - **ETL** tính các giá trị trên từng dòng (cờ, điểm, hiệu số, tuổi, phí chênh…).
  - **Kho chỉ lưu** fact chi tiết, chỉ thêm dòng mới, không có bảng tổng hợp.
  - **Tổng hợp làm ở SSAS / Power BI.** Đó là việc của giai đoạn này.
- Tài liệu nên đọc trong repo:
  - `docs/Tinh_toan_trong_ETL_va_Measure.md`, **mục C**: danh sách measure, công thức gợi ý, câu hỏi nghiệp vụ.
  - `docs/Dien_giai_chi_tiet_SSIS.md`: các cột được tính thế nào.
  - `docs/hinh/Hinh_2_1_Galaxy_Schema.png`: sơ đồ kho.
  - `sql/01_create_dw.sql`: định nghĩa bảng.

## B. Kho dữ liệu `football_dwh_dw`

### Fact (grain chi tiết nhất)

| Fact | Grain | Khóa dimension | Measure |
|---|---|---|---|
| `fact_team_match` (177.916 dòng) | 1 trận × 1 đội (mỗi trận 2 dòng) | date_key, season_key, competition_key, match_key, club_key, **opponent_club_key**, manager_key, **opponent_manager_key** | is_home, goals_for, goals_against, is_win, is_draw, is_loss, is_clean_sheet, points, goal_difference, league_position |
| `fact_player_appearance` (1.894.347) | 1 cầu thủ × 1 trận | date_key, season_key, competition_key, match_key, player_key, club_key | minutes_played, goals, assists, yellow_cards, red_cards, appearance_count (=1); appearance_id (degenerate) |
| `fact_player_valuation` (656.301) | 1 cầu thủ × 1 lần định giá | date_key, player_key, club_key, competition_key (**không có season_key**) | market_value_eur, value_change_eur, age_at_valuation, valuation_count (=1) |
| `fact_transfer` (175.165) | 1 thương vụ | date_key, season_key, player_key, **from_club_key**, **to_club_key**, transfer_type_key | transfer_fee_eur (NULL = không công bố), market_value_eur, fee_premium_eur, age_at_transfer, is_youth_transfer, transfer_count (=1) |

### Dimension (mỗi dim có dòng Unknown key = -1, tên "Không xác định")

| Dim | Cột chính | Hierarchy gợi ý |
|---|---|---|
| `dim_date` | date_key (yyyymmdd), full_date, year, quarter, month, month_name, day_of_week, day_name, is_weekend | Năm → Quý → Tháng → Ngày |
| `dim_season` | season_key, season_start_year, season_label (2024/25), season_short | |
| `dim_competition` | competition_key, competition_id (GB1, ES1, L1, IT1, FR1…), competition_name, competition_type, competition_sub_type, country_name, confederation | Liên đoàn → Quốc gia → Giải |
| `dim_club` (SCD1/2/3) | club_key, club_id, club_name, club_type (Club / National Team / Other), country_name, confederation, current_league_name, previous_league_name (SCD3), stadium_name, stadium_capacity_band (SCD2), is_current | Liên đoàn → Quốc gia → CLB |
| `dim_player` (SCD1/2) | player_key, player_id, full_name, date_of_birth, citizenship, position (Attack / Midfield / Defender / Goalkeeper), sub_position, foot, height_band, agent_name, international_caps_band, is_current | Vị trí → Vị trí chi tiết → Cầu thủ |
| `dim_match` | match_key, game_id, round, round_type, stadium, referee, home_formation, away_formation, attendance_band | |
| `dim_manager` | manager_key, manager_name | |
| `dim_transfer_type` | transfer_type_key, fee_status (Có phí / Miễn phí hoặc cho mượn / Không công bố), fee_band (< 1 triệu, 1-10 triệu, 10-50 triệu, > 50 triệu, Không áp dụng) | Trạng thái phí → Khoảng phí |

### Role-playing (một dim, nhiều vai trò)

- **Dim_Club** có 4 vai trò: CLB, CLB đối thủ (Fact_Team_Match); CLB đi, CLB đến (Fact_Transfer).
- **Dim_Manager** có 2 vai trò: HLV, HLV đối thủ.
- **Dim_Date** dùng chung cho cả 4 fact.

## C. Công cụ, cấu trúc project và quy tắc làm chung

- **SSAS Multidimensional** (cube). Mở bằng Visual Studio (2022 hoặc 2026) có extension *Microsoft Analysis Services Projects*. Server SSAS `localhost` (instance mặc định, chế độ Multidimensional). Lý do: môn học yêu cầu cube và các thao tác OLAP roll-up, drill-down, slice, dice, pivot. Ngoài ra `market_value_eur` cần `LastNonEmpty`.
- **Power BI** do **Phần 4** làm toàn bộ, kết nối *Live connection* vào cube. **Phần 4 không làm SSAS.** Phần 1–3 làm SSAS, rồi gửi câu hỏi nghiệp vụ và visual đề xuất cho Phần 4.

### Cấu trúc project (giống SSIS: khung đã tạo sẵn, mỗi phần vào điền phần của mình)

```
ssas-transfermarkt/Football_DAWH_SSAS/
├── Football_DAWH_SSAS.slnx
└── Football_DAWH_SSAS/
    ├── Football DWH.ds              Data Source           – khung (có sẵn)
    ├── Football DWH.dsv             Data Source View      – khung (có sẵn)
    ├── Ngay.dim, Mua giai.dim       Dimension thời gian    – khung (có sẵn, đã điền)
    ├── Giai dau.dim, Tran dau.dim, HLV.dim, CLB.dim        – Phần 1
    ├── Loai chuyen nhuong.dim, Cau thu.dim                 – Phần 3
    ├── Football DWH.cube            Cube tổng (khung, measure gốc) – có sẵn, giữ nguyên
    ├── Hieu suat doi bong.cube      Cube riêng của Phần 1 – tự tạo
    ├── Hieu suat cau thu.cube       Cube riêng của Phần 2 – tự tạo
    └── Thi truong cau thu.cube      Cube riêng của Phần 3 – đã tạo (mẫu)
```

- Mỗi file `.dim` là một file riêng, nên ai sửa dim của người nấy thì không bị xung đột.
- **Mỗi phần có một file `.cube` riêng**, nên ai sửa cube của người nấy, không lo xung đột.
- **Chỉ `.dsv` là file dùng chung.** Ai cần sửa DSV phải **giữ lượt**: nhắn nhóm "đang giữ DSV", `git pull`, sửa, deploy, commit + push, rồi nhắn "trả DSV". Không để 2 người sửa cùng lúc, vì XML này không merge được.
- Cube `Football DWH` giữ nguyên làm cube tổng. **Không viết calculated member / KPI vào cube này.** Các khối *Phần 1–3* trong tab Calculations của nó để trống.
- Cần thêm cột tính trong DSV (Named Calculation) thì nhờ người tạo khung thêm.
- Không commit tên server riêng. Máy dùng instance khác `localhost` thì sửa `Football DWH.ds` trên máy mình và chạy `git update-index --skip-worktree` cho file đó.
- Tên measure tiếng Việt, đúng như trong `Tinh_toan_trong_ETL_va_Measure.md` (Điểm, Tỉ lệ thắng, Bàn mỗi 90 phút…).


### Mỗi phần tạo một cube riêng

Không dồn mọi thứ vào cube `Football DWH`. Mỗi phần tạo **một cube riêng** cho quy trình nghiệp vụ của mình. Cube đó chỉ chứa fact và dimension cần thiết, và phải nói rõ **giá trị mang lại** (trả lời câu hỏi gì, hỗ trợ quyết định gì).

| Cube | File | Phần | Fact (measure group) | Cube dimension | Giá trị mang lại |
|---|---|---|---|---|---|
| Football DWH | `Football DWH.cube` | khung (có sẵn, giữ nguyên) | cả 4 fact, chỉ measure gốc | tất cả | Cube tổng để kiểm tra số liệu và làm trang *Tổng quan* |
| **Hiệu suất đội bóng** | `Hieu suat doi bong.cube` | 1 | Trận đấu đội (fact_team_match) | Ngày, Mùa giải, Giải đấu, Trận đấu, CLB, CLB đối thủ, HLV, HLV đối thủ | Bảng xếp hạng, phong độ theo mùa, HLV hiệu quả, lợi thế sân nhà → đánh giá thành tích, giữ hay thay HLV, đặt mục tiêu điểm |
| **Hiệu suất cầu thủ** | `Hieu suat cau thu.cube` | 2 | Lượt ra sân + Trận có ra sân (Distinct Count match_key) | Ngày, Mùa giải, Giải đấu, Trận đấu, CLB, Cầu thủ | Vua phá lưới, bàn mỗi 90 phút, cầu thủ ra sân nhiều, trọng tài khắt khe → tuyển trạch, đánh giá và gia hạn cầu thủ |
| **Thị trường cầu thủ** | `Thi truong cau thu.cube` | 3 | Định giá + Chuyển nhượng | Ngày, Mùa giải, Giải đấu, Cầu thủ, Tuổi, CLB, CLB đi, CLB đến, Loại chuyển nhượng | Giá trị đội hình, độ tuổi đỉnh giá trị, chi tiêu ròng, mua đắt hay rẻ, tỉ lệ thương vụ miễn phí / đội trẻ → quản lý tài sản cầu thủ và ngân sách chuyển nhượng (**đã làm xong**, dùng làm mẫu) |

Cách tạo cube riêng trong Visual Studio:
1. Chuột phải **Cubes → New Cube** → *Use existing tables*.
2. **Measure group tables:** chỉ chọn fact của phần mình.
3. **Measures:** chọn các cột measure và các Named Calculation đã có trong DSV (ví dụ `home_win`). Bỏ cột khóa và `batch_id`. Đổi tên sang tiếng Việt.
   - Measure Sum trên cột tinyint/smallint: đặt **DataType** của measure là Integer (hoặc BigInt nếu là tiền), để cộng dồn không bị tràn số.
4. **Dimensions:** chỉ chọn các dim có sẵn mà phần mình dùng. **Không tạo dim mới bằng wizard.**
5. **Đặt tên cube** theo bảng trên.
6. Ở khung Dimensions của cube, đổi tên các bản role-playing (CLB đối thủ, CLB đi, CLB đến, HLV đối thủ).
7. Kiểm tra tab **Dimension Usage**.
8. Chọn cube → Properties → **Description**: ghi giá trị mang lại. Ghi lại nội dung này ở đầu tab Calculations dưới dạng chú thích `/* … */`.
9. Viết calculated member và KPI vào tab **Calculations / KPIs** của **cube mình**.
10. Deploy, kiểm tra số liệu với SQL.

Cube `Thi truong cau thu.cube` là mẫu đầy đủ: có Description, MDX, KPI và đã khớp SQL.

### Điểm dễ sai

| Điểm | Cách đúng |
|---|---|
| Tỉ lệ (tỉ lệ thắng, bàn / 90 phút…) | Calculated member = measure gốc / measure gốc. Không tạo measure SUM của tỉ lệ |
| Tuổi, `league_position` | Không cộng; chỉ AVG / MIN / MAX (calculated member = Sum / Count) |
| `market_value_eur` | Semi-additive: **LastNonEmpty** theo thời gian, cộng theo cầu thủ / CLB |
| `transfer_fee_eur` NULL | Giữ NULL; đếm riêng "không công bố". Đổi NULL thành 0 sẽ làm phí trung bình sai |
| Dòng Unknown (-1) | Giữ; khi xếp hạng thì lọc bỏ "Không xác định" |
| `ASSOCIATED_MEASURE_GROUP` trong `CREATE MEMBER` | Ghi **tên hiển thị** của measure group (ví dụ 'Định giá'), không ghi ID ('Fact Player Valuation'). Ghi ID sẽ báo lỗi *measure group was not found* |
| Thuộc tính SCD2 | Fact tra theo phiên bản hiện tại, nên vị trí / sân / người đại diện là giá trị hiện tại |

### Kết quả chuẩn để kiểm tra cube (đã đúng trên SQL)

- Premier League 2024/25: Liverpool 38 trận, **84 điểm**, +45; Arsenal 74; Man City 71; Chelsea 69; Newcastle 66.
- Vua phá lưới Premier League 2024/25: **Salah 29 bàn** (0,77 / 90 phút), Isak 23, Haaland 22.
- Thương vụ đội trẻ (`is_youth_transfer = 1`): 36.443 thương vụ, tuổi trung bình 15,4. Chuyên nghiệp: 138.695 thương vụ, tuổi trung bình 22,6.

## D. Các phần việc và thứ tự

### Khung SSAS (đã tạo sẵn)

Project `Football_DAWH_SSAS` đã có sẵn: Data Source, DSV (12 bảng + Named Calculation), 8 dimension (Ngày, Mùa giải đã điền đủ; 6 dim còn lại chỉ có khóa và tên), cube tổng `Football DWH` với 5 measure group, role-playing dimension, Dimension Usage. Cứ `git pull` là có. Mỗi phần tự tạo **cube riêng** của mình theo mục C (*Mỗi phần tạo một cube riêng*). Cube `Thị trường cầu thủ` của Phần 3 đã có sẵn để làm mẫu.

### 4 phần việc (nhóm tự nhận)

| Phần | Nội dung | Dimension phải điền | File context |
|---|---|---|---|
| **1** | Hiệu suất đội bóng và HLV (Fact_Team_Match) | Giải đấu, Trận đấu, HLV, CLB | `Phan_1_Hieu_suat_doi_bong.md` |
| **2** | Hiệu suất cầu thủ (Fact_Player_Appearance) + tổng hợp bảng đối chiếu cube = SQL | – | `Phan_2_Hieu_suat_cau_thu.md` |
| **3** | Giá trị cầu thủ và chuyển nhượng (Fact_Player_Valuation, Fact_Transfer) | Loại chuyển nhượng, Cầu thủ | `Phan_3_Gia_tri_va_chuyen_nhuong.md` |
| **4** | Toàn bộ Power BI (không làm SSAS) | – | `Phan_4_PowerBI.md` |

### Thứ tự

| Giai đoạn | Phần 1, 2, 3 | Phần 4 |
|---|---|---|
| 1 | Điền dim của phần mình; viết câu hỏi, SQL đối chiếu, nháp MDX | Theme, layout, phác thảo các trang (có thể Import thẳng từ kho để làm nháp) |
| 2 | Tạo cube riêng, viết MDX / KPI vào cube của mình, kiểm tra cube = SQL, minh họa OLAP | Dựng các trang Power BI khi cube có measure |
| 3 | Ảnh minh chứng, phần báo cáo; Phần 2 tổng hợp bảng đối chiếu | Hoàn thiện Power BI, ảnh từng trang |

## E. Phần việc: hiệu suất cầu thủ + tổng hợp đối chiếu số liệu

**Fact:** `fact_player_appearance`. **Dimension:** Ngày, Mùa giải, Giải đấu, Trận đấu, Cầu thủ, CLB.

### E0. Cube riêng của phần này: **Hiệu suất cầu thủ** (`Hieu suat cau thu.cube`)
- Measure group *Lượt ra sân* từ `fact_player_appearance`: Số phút, Bàn thắng cầu thủ, Kiến tạo, Thẻ vàng, Thẻ đỏ, Số trận ra sân.
- Measure group thứ hai *Trận có ra sân*: New Measure → Usage *Distinct count* trên `match_key`, dùng cho thẻ phạt mỗi trận.
- Cube dimension: Ngày, Mùa giải, Giải đấu, Trận đấu, CLB, Cầu thủ.
- Description (giá trị mang lại): vua phá lưới, bàn mỗi 90 phút, cầu thủ ra sân nhiều, trọng tài khắt khe → tuyển trạch, đánh giá và gia hạn cầu thủ.
- Calculated member và KPI viết vào tab Calculations / KPIs của **cube này**. `ASSOCIATED_MEASURE_GROUP = 'Lượt ra sân'`.
- Dim Cầu thủ đã được Phần 3 điền đủ, gồm hierarchy *Vị trí - Vị trí chi tiết - Cầu thủ*. Dùng luôn, không cần sửa.

### E1. Câu hỏi nghiệp vụ
| # | Câu hỏi | Measure | Chiều |
|---|---|---|---|
| Q1 | Vua phá lưới, vua kiến tạo từng giải, từng mùa? | Bàn thắng, Kiến tạo | Mùa giải, Giải đấu, Cầu thủ |
| Q2 | Tiền đạo nào ghi bàn hiệu quả nhất mỗi 90 phút (tối thiểu 900 phút)? | Bàn mỗi 90 phút, Số phút | Cầu thủ (vị trí Attack) |
| Q3 | Cầu thủ nào ra sân nhiều nhất? | Số trận ra sân | Cầu thủ, CLB |
| Q4 | Vị trí nào đóng góp bàn thắng nhiều nhất ở mỗi giải? | Bàn thắng | Vị trí × Giải đấu |
| Q5 | Trọng tài nào khắt khe nhất? | Thẻ phạt mỗi trận | Trận đấu (trọng tài) |
| Q6 | Cầu thủ trẻ (dưới 21) nào thi đấu nhiều phút nhất? | Số phút | Cầu thủ, Mùa giải |

### E2. Measure
| Measure | Loại | Công thức | Tính chất |
|---|---|---|---|
| Bàn thắng, Kiến tạo, Số phút | Gốc | Sum goals / assists / minutes_played | Additive |
| Số trận ra sân | Gốc | Sum appearance_count | Additive |
| Thẻ vàng, Thẻ đỏ | Gốc | Sum yellow_cards / red_cards | Additive |
| Số trận (distinct) | Gốc | DistinctCount match_key (measure group riêng) | Non-additive |
| Bàn mỗi 90 phút | Calculated | [Bàn thắng] × 90 / [Số phút] | Non-additive |
| Bàn + kiến tạo mỗi 90 phút | Calculated | ([Bàn thắng] + [Kiến tạo]) × 90 / [Số phút] | Non-additive |
| Thẻ phạt mỗi trận | Calculated | ([Thẻ vàng] + [Thẻ đỏ]) / [Số trận distinct] | Non-additive |

**KPI:** Bàn mỗi 90 phút của tiền đạo, mục tiêu ≥ 0,5.

### E3. Thao tác OLAP minh họa
- Roll-up: Bàn thắng từ Cầu thủ → CLB → Giải đấu.
- Drill-down: Bàn thắng từ Năm → Quý → Tháng.
- Slice: chỉ vị trí Attack.
- Dice: top 5 giải (GB1, ES1, L1, IT1, FR1), 3 mùa gần nhất.
- Pivot: đổi trục Vị trí × Giải đấu.

### E4. Đề xuất visual gửi Phần 4 (làm Power BI), trang *Cầu thủ*
- Top 10 vua phá lưới / kiến tạo, có slicer Mùa giải và Giải đấu.
- Biểu đồ phân tán Số phút × Bàn mỗi 90 phút.
- Ma trận Vị trí × Giải đấu theo Bàn thắng.
- Top trọng tài theo Thẻ phạt mỗi trận.

### E5. Tổng hợp đối chiếu (giai đoạn 3)
- Thu bảng đối chiếu cube = SQL của Phần 1, 3 (và số liệu trên các trang Power BI của Phần 4), gộp thành một bảng chung cho báo cáo (cột: người, câu hỏi, bộ lọc, cube, SQL, khớp).
- Chỗ nào lệch thì tìm nguyên nhân. Thường là Dimension Usage nối sai vai trò, AggregateFunction sai, hoặc chưa lọc dòng -1.

### E6. SQL đối chiếu mẫu (Q1)
```sql
SELECT TOP 10 p.full_name, SUM(a.goals) ban_thang, SUM(a.minutes_played) so_phut,
       CAST(SUM(a.goals) * 90.0 / NULLIF(SUM(a.minutes_played), 0) AS DECIMAL(4,2)) ban_moi_90
FROM fact_player_appearance a
JOIN dim_player p      ON p.player_key = a.player_key
JOIN dim_competition k ON k.competition_key = a.competition_key
JOIN dim_season s      ON s.season_key = a.season_key
WHERE k.competition_id = 'GB1' AND s.season_label = '2024/25'
GROUP BY p.full_name ORDER BY ban_thang DESC;   -- Salah 29, 0.77
```

## Kết quả cần nộp (Definition of done)

1. Mọi measure trong phần việc có giá trị trên cube **khớp với SQL đối chiếu** (ghi bảng: câu hỏi, bộ lọc, kết quả cube, kết quả SQL).
2. Ảnh minh chứng: Phần 1–3 chụp cấu hình trong Visual Studio, kết quả browse cube và 5 thao tác OLAP; Phần 4 chụp từng trang Power BI.
3. Đoạn viết cho báo cáo: câu hỏi nghiệp vụ → measure dùng → kết quả → ý nghĩa / quyết định hỗ trợ.

## Cách dùng file này với trợ lý AI

Dán toàn bộ file này vào đầu cuộc trò chuyện, rồi hỏi từng bước, ví dụ:
- "Viết MDX cho measure … theo context trên."
- "Viết SQL đối chiếu cho câu hỏi Q2."
- "Hướng dẫn tạo KPI … trong SSAS Multidimensional."
