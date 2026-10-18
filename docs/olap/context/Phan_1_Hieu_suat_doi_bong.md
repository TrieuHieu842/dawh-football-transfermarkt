# Context giai đoạn SSAS & Power BI – Phần 1

> Nội dung: **Hiệu suất đội bóng và HLV**. File này tự đủ thông tin; ai nhận phần này có thể dán nguyên vào trợ lý AI để làm tiếp.

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
    └── Football DWH.cube            Cube (4 measure group) – khung có sẵn; Calculations / KPI: mỗi phần một khối (1, 2, 3)
```

- Mỗi file `.dim` là một file riêng, nên ai sửa dim của người nấy thì không bị xung đột.
- **`.dsv` và `.cube` dùng chung.** Ai cần sửa phải **giữ lượt**: nhắn nhóm "đang giữ cube", `git pull`, sửa, deploy, commit + push, rồi nhắn "trả cube". Không để 2 người sửa cùng lúc, vì hai bản XML này không merge được.
- Tab *Calculations* của cube đã chia sẵn khối cho từng phần (`/* ===== Phần 1 … ===== */`). Chỉ viết vào khối của mình.
- Cần thêm cột tính trong DSV (Named Calculation) thì nhờ người tạo khung thêm.
- Không commit tên server riêng. Máy dùng instance khác `localhost` thì sửa `Football DWH.ds` trên máy mình và chạy `git update-index --skip-worktree` cho file đó.
- Tên measure tiếng Việt, đúng như trong `Tinh_toan_trong_ETL_va_Measure.md` (Điểm, Tỉ lệ thắng, Bàn mỗi 90 phút…).

### Điểm dễ sai

| Điểm | Cách đúng |
|---|---|
| Tỉ lệ (tỉ lệ thắng, bàn / 90 phút…) | Calculated member = measure gốc / measure gốc. Không tạo measure SUM của tỉ lệ |
| Tuổi, `league_position` | Không cộng; chỉ AVG / MIN / MAX (calculated member = Sum / Count) |
| `market_value_eur` | Semi-additive: **LastNonEmpty** theo thời gian, cộng theo cầu thủ / CLB |
| `transfer_fee_eur` NULL | Giữ NULL; đếm riêng "không công bố". Đổi NULL thành 0 sẽ làm phí trung bình sai |
| Dòng Unknown (-1) | Giữ; khi xếp hạng thì lọc bỏ "Không xác định" |
| Thuộc tính SCD2 | Fact tra theo phiên bản hiện tại, nên vị trí / sân / người đại diện là giá trị hiện tại |

### Kết quả chuẩn để kiểm tra cube (đã đúng trên SQL)

- Premier League 2024/25: Liverpool 38 trận, **84 điểm**, +45; Arsenal 74; Man City 71; Chelsea 69; Newcastle 66.
- Vua phá lưới Premier League 2024/25: **Salah 29 bàn** (0,77 / 90 phút), Isak 23, Haaland 22.
- Thương vụ đội trẻ (`is_youth_transfer = 1`): 36.443 thương vụ, tuổi trung bình 15,4. Chuyên nghiệp: 138.695 thương vụ, tuổi trung bình 22,6.

## D. Các phần việc và thứ tự

### Khung SSAS (đã tạo sẵn)

Project `Football_DAWH_SSAS` đã có sẵn: Data Source, DSV (12 bảng + Named Calculation), 8 dimension (Ngày, Mùa giải đã điền đủ; 6 dim còn lại chỉ có khóa và tên), cube `Football DWH` với 5 measure group, role-playing dimension, Dimension Usage và khung tab Calculations chia khối theo phần. Cứ `git pull` là có.

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
| 2 | Đưa MDX / KPI vào cube (giữ lượt), kiểm tra cube = SQL, minh họa OLAP | Dựng các trang Power BI khi cube có measure |
| 3 | Ảnh minh chứng, phần báo cáo; Phần 2 tổng hợp bảng đối chiếu | Hoàn thiện Power BI, ảnh từng trang |

## E. Phần việc: hiệu suất đội bóng và HLV

**Fact:** `fact_team_match`. **Dimension:** Ngày, Mùa giải, Giải đấu, Trận đấu, CLB, CLB đối thủ, HLV, HLV đối thủ.

### E0. Điền 4 dimension của phần này (khung đã tạo sẵn, dim chỉ có khóa và tên; mỗi dim là 1 file riêng, sửa thoải mái)
| Dimension | Attribute | Hierarchy | Lưu ý |
|---|---|---|---|
| Giải đấu (`Giai dau.dim`) | competition_name, competition_id, competition_type, competition_sub_type, country_name, confederation | Liên đoàn → Quốc gia → Giải | Attribute Relationships Giải → Quốc gia → Liên đoàn |
| Trận đấu (`Tran dau.dim`) | game_id, round, round_type, referee, stadium, home_formation, away_formation, attendance_band | Loại vòng → Vòng | Phần 2 dùng referee để phân tích trọng tài |
| HLV (`HLV.dim`) | manager_name | | Trong cube có 2 vai trò: HLV, HLV đối thủ |
| CLB (`CLB.dim`) | club_name (NameColumn), club_type, country_name, confederation, current_league_name, previous_league_name, stadium_name, stadium_capacity_band, is_current | Liên đoàn → Quốc gia → CLB | Một CLB có thể có nhiều phiên bản SCD2 (khác club_key), nên KeyColumn là club_key. Cube dùng dim này 4 vai trò (CLB, CLB đối thủ, CLB đi, CLB đến) |

Calculated member và KPI viết vào khối *Phần 1* ở tab Calculations của cube (nhớ giữ lượt cube). Measure gốc Số trận sân nhà và Thắng sân nhà đã có sẵn.


### E1. Câu hỏi nghiệp vụ
| # | Câu hỏi | Measure | Chiều |
|---|---|---|---|
| Q1 | Bảng xếp hạng cuối mùa của một giải (ví dụ Premier League 2024/25)? | Điểm, Hiệu số, Số trận | Mùa giải, Giải đấu, CLB |
| Q2 | CLB nào thắng nhiều nhất mỗi mùa? | Thắng / Hòa / Thua | Mùa giải, CLB |
| Q3 | HLV nào có tỉ lệ thắng cao nhất (tối thiểu 50 trận)? | Tỉ lệ thắng, Số trận | HLV |
| Q4 | Giải nào có lợi thế sân nhà lớn nhất? | Tỉ lệ thắng sân nhà | Giải đấu |
| Q5 | Giải nào ghi nhiều bàn mỗi trận nhất, xu hướng qua các mùa? | Bàn thắng mỗi trận | Giải đấu, Mùa giải |
| Q6 | Đội nào giữ sạch lưới nhiều nhất mùa? | Số trận sạch lưới | Mùa giải, CLB |

### E2. Measure
| Measure | Loại | Công thức | Tính chất |
|---|---|---|---|
| Số trận | Gốc | Count dòng | Additive |
| Thắng / Hòa / Thua | Gốc | Sum is_win / is_draw / is_loss | Additive |
| Điểm | Gốc | Sum points | Additive |
| Hiệu số | Gốc | Sum goal_difference | Additive |
| Bàn thắng / Bàn thua | Gốc | Sum goals_for / goals_against | Additive |
| Số trận sạch lưới | Gốc | Sum is_clean_sheet | Additive |
| Tỉ lệ thắng | Calculated | [Thắng] / [Số trận] | Non-additive |
| Tỉ lệ thắng sân nhà | Calculated | Tỉ lệ thắng với is_home = 1 (cần attribute is_home hoặc measure Sum is_win × is_home tính trong DSV) | Non-additive |
| Bàn thắng mỗi trận | Calculated | [Bàn thắng] / [Số trận] | Non-additive |

**KPI:** Tỉ lệ thắng của HLV, mục tiêu ≥ 50%; Status xanh / vàng / đỏ; Trend so với mùa trước.

### E3. Thao tác OLAP minh họa (mỗi thao tác 1 ảnh)
- Roll-up: Điểm từ CLB → Quốc gia → Liên đoàn.
- Drill-down: Bàn thắng từ Năm → Quý → Tháng.
- Slice: chỉ mùa 2024/25.
- Dice: Premier League + La Liga, mùa 2022/23–2024/25.
- Pivot: đổi trục Giải đấu × Mùa giải.

### E4. Đề xuất visual gửi Phần 4 (làm Power BI), trang *Đội bóng & HLV*
- Bảng xếp hạng, có slicer Mùa giải và Giải đấu.
- Đường xu hướng Điểm / Bàn mỗi trận qua các mùa.
- Top 10 HLV theo Tỉ lệ thắng.
- Cột Tỉ lệ thắng sân nhà theo giải.

### E5. SQL đối chiếu mẫu (Q1)
```sql
SELECT TOP 20 c.club_name, COUNT(*) so_tran, SUM(f.points) diem, SUM(f.goal_difference) hieu_so
FROM fact_team_match f
JOIN dim_club c        ON c.club_key = f.club_key
JOIN dim_competition k ON k.competition_key = f.competition_key
JOIN dim_season s      ON s.season_key = f.season_key
WHERE k.competition_id = 'GB1' AND s.season_label = '2024/25'
GROUP BY c.club_name ORDER BY diem DESC, hieu_so DESC;   -- Liverpool 84, +45
```
Lưu ý: mỗi trận có 2 dòng, nên số trận của **một giải** = COUNT / 2. Còn số trận của **một CLB** = COUNT.

## Kết quả cần nộp (Definition of done)

1. Mọi measure trong phần việc có giá trị trên cube **khớp với SQL đối chiếu** (ghi bảng: câu hỏi, bộ lọc, kết quả cube, kết quả SQL).
2. Ảnh minh chứng: Phần 1–3 chụp cấu hình trong Visual Studio, kết quả browse cube và 5 thao tác OLAP; Phần 4 chụp từng trang Power BI.
3. Đoạn viết cho báo cáo: câu hỏi nghiệp vụ → measure dùng → kết quả → ý nghĩa / quyết định hỗ trợ.

## Cách dùng file này với trợ lý AI

Dán toàn bộ file này vào đầu cuộc trò chuyện, rồi hỏi từng bước, ví dụ:
- "Viết MDX cho measure … theo context trên."
- "Viết SQL đối chiếu cho câu hỏi Q2."
- "Hướng dẫn tạo KPI … trong SSAS Multidimensional."
