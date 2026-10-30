# Hướng dẫn chi tiết Cube SSAS – Phần 4: Kỷ luật Sân cỏ & Trọng tài Điều hành

> **Mục tiêu tài liệu**: Tài liệu này được thiết kế để giải thích cặn kẽ từng bước xây dựng Cube `Ky luat va Trong tai.cube` (`Kỷ luật và Trọng tài`), lý do lựa chọn mô hình, ý nghĩa các thước đo và câu truy vấn MDX, cùng bộ câu hỏi phản biện thực tế để sinh viên tự tin trả lời đạt điểm tối đa khi vấn đáp trước Hội đồng/Giảng viên.

---

## 1. Ý nghĩa Nghiệp vụ & Mục tiêu Phân tích

Trong bóng đá hiện đại, **tính kỷ luật sân cỏ** và **công tác trọng tài** là hai yếu tố có tác động mang tính quyết định đến kết quả trận đấu, chiến thuật của huấn luyện viên, cũng như danh tiếng và kinh tế của câu lạc bộ:
1. **Quản trị rủi ro thi đấu**: Nhận thẻ phạt (đặc biệt là thẻ đỏ) làm thay đổi hoàn toàn cục diện trận đấu, đẩy đội bóng vào thế thiếu người, gia tăng nguy cơ thủng lưới và thất bại.
2. **Đánh giá phong cách trọng tài**: Mỗi trọng tài có ngưỡng xử lý tình huống và độ nghiêm khắc khác nhau. Việc phân tích dữ liệu lịch sử giúp ban huấn luyện có chiến lược dặn dò cầu thủ hạn chế phạm lỗi chiến thuật với các trọng tài có xu hướng rút thẻ quyết liệt.
3. **Đánh giá tinh thần Fair-play CLB**: Các giải đấu hàng đầu thế giới (như Premier League, La Liga, UEFA) đều áp dụng thang điểm Fair-play để trao giải thưởng, phân bổ suất tham dự cúp châu Âu hoặc xử phạt hành chính các CLB có lối chơi bạo lực.
4. **Phân hóa lối chơi (Cống hiến vs Chặt chém)**: Đánh giá mối tương quan giữa số bàn thắng ghi được và số thẻ phạt phải nhận, giúp nhận diện các đội bóng thi đấu cống hiến, hoa mỹ đối lập với các đội thiên về va chạm thể lực.

---

## 2. Bước 1: Lựa chọn Mô hình & Bảng Fact trung tâm

### 2.1. Tại sao chọn bảng `fact_player_appearance` làm Fact trung tâm?
* **Grain của Fact**: **1 cầu thủ $\times$ 1 trận đấu** (Khoảng 1.894.347 dòng dữ liệu).
* **Lý do lựa chọn (Câu hỏi vấn đáp cốt lõi)**:
  * *Tại sao không dùng `fact_team_match`?* 
    * Trong `fact_team_match`, mức độ chi tiết (grain) là **1 đội bóng $\times$ 1 trận đấu**. Nếu dùng bảng này, chúng ta chỉ biết tổng số thẻ của cả đội mà hoàn toàn mất đi thông tin **cầu thủ nào nhận thẻ**, **vị trí thi đấu nào hay dính thẻ nhất** (Hậu vệ hay Tiền vệ?), và **thời gian thi đấu cụ thể (phút)** để tính tần suất dính thẻ.
  * *Ưu thế của `fact_player_appearance`*:
    * Bảng này lưu vết chi tiết từng cá nhân ra sân: thẻ vàng, thẻ đỏ, số phút thi đấu, bàn thắng, kiến tạo.
    * Cho phép phân tích linh hoạt 2 chiều: **từ chi tiết cá nhân cầu thủ** (roll-up) lên **cấp độ toàn đội bóng (CLB)** và **toàn giải đấu**.
    * Liên kết trực tiếp với mã trận đấu (`match_key`), qua đó liên kết sang trọng tài (`referee`) bắt chính trận đấu đó.

---

## 3. Bước 2: Lựa chọn và Phân cấp các Dimension (Chiều phân tích)

Cube sử dụng **6 Dimension** liên kết với Fact theo mô hình Star Schema:

| Dimension | Thuộc tính chính (Attributes) | Hierarchy (Hệ thống phân cấp) | Ý nghĩa nghiệp vụ phân tích |
|---|---|---|---|
| **Trận đấu** (`Tran dau.dim`) | `referee` (Trọng tài), `stadium` (Sân vận động), `round_type` (Loại vòng) | Loại vòng $\rightarrow$ Vòng đấu | Đo lường mức độ nghiêm khắc của từng trọng tài; so sánh thẻ phạt giữa vòng bảng và vòng knock-out loại trực tiếp. |
| **Cầu thủ** (`Cau thu.dim`) | `full_name`, `position` (Vị trí thi đấu), `sub_position`, `citizenship` | Vị trí $\rightarrow$ Vị trí chi tiết $\rightarrow$ Cầu thủ | Phát hiện vị trí có rủi ro nhận thẻ cao nhất trên sân (Trung vệ vs Tiền vệ phòng ngự); nhận diện các cầu thủ "ngổ ngáo". |
| **CLB** (`CLB.dim`) | `club_name`, `country_name`, `confederation` | Liên đoàn $\rightarrow$ Quốc gia $\rightarrow$ CLB | Xếp hạng phong cách thi đấu và điểm Fair-play của các câu lạc bộ; tìm ra CLB chơi bạo lực nhất hoặc trong sạch nhất. |
| **Giải đấu** (`Giai dau.dim`) | `competition_name`, `competition_type`, `confederation` | Liên đoàn $\rightarrow$ Quốc gia $\rightarrow$ Giải đấu | So sánh mức độ va chạm giữa các giải đấu (Ví dụ: La Liga và Serie A thường phạt nhiều thẻ hơn Premier League). |
| **Mùa giải** (`Mua giai.dim`) | `season_label` (ví dụ `2024/25`) | Mùa giải | Theo dõi xu hướng biến động kỷ luật qua các năm; đánh giá hiệu quả của các đạo luật mới (như luật phạt lỗi phản ứng trọng tài). |
| **Ngày** (`Ngay.dim`) | `full_date`, `year`, `quarter`, `month` | Năm $\rightarrow$ Quý $\rightarrow$ Tháng $\rightarrow$ Ngày | Phân tích biến động thẻ phạt theo chu kỳ thời gian trong năm (giai đoạn đầu mùa vs giai đoạn nước rút cuối mùa). |

---

## 4. Bước 3: Thiết kế Kiến trúc 3 Measure Groups (Kỹ thuật then chốt SSAS)

Trong SSAS Multidimensional, Cube được thiết kế phân tách thành **3 Measure Groups độc lập**:

```
                              ┌──────────────────────────────────────────────┐
                              │     Cube: [Kỷ luật và Trọng tài]             │
                              └──────────────────────┬───────────────────────┘
                                                     │
         ┌───────────────────────────────────────────┼───────────────────────────────────────────┐
         ▼                                           ▼                                           ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐   ┌───────────────────────────────┐
│ Measure Group 1:              │   │ Measure Group 2:              │   │ Measure Group 3:              │
│ [Kỷ luật thi đấu]             │   │ [Trận đấu điều hành]          │   │ [Cầu thủ ra sân]              │
├───────────────────────────────┤   ├───────────────────────────────┤   ├───────────────────────────────┤
│ • Loại: SUM (Cộng dồn)        │   │ • Loại: DistinctCount         │   │ • Loại: DistinctCount         │
│ • Thẻ vàng, Thẻ đỏ            │   │ • Cột: match_key              │   │ • Cột: player_key             │
│ • Số phút thi đấu, Bàn thắng  │   │ • Mục đích: Đếm số trận duy   │   │ • Mục đích: Đếm số cầu thủ    │
│ • Kiến tạo, Lượt ra sân       │   │   nhất không bị trùng lặp     │   │   thực tế ra sân thi đấu      │
└───────────────────────────────┘   └───────────────────────────────┘   └───────────────────────────────┘
```

### Tại sao phải tách thành 3 Measure Groups? (Câu hỏi trọng tâm bảo vệ đồ án)
* **Quy tắc vàng của SSAS Multidimensional**: Các phép toán `DistinctCount` (đếm phân biệt) có thuật toán xử lý dữ liệu khác biệt hoàn toàn so với các phép toán cộng dồn thông thường (`SUM`). Phép `DistinctCount` yêu cầu tạo các cấu trúc chỉ mục bitmap nội bộ đặc biệt để loại trừ trùng lặp khi tổng hợp đa chiều.
* **Tối ưu hóa hiệu năng và lưu trữ**:
  1. Nếu gộp `DistinctCount` chung vào Measure Group chứa các thước đo `SUM`, SSAS không thể tối ưu hóa cấu trúc nén MOLAP, làm giảm nghiêm trọng tốc độ truy vấn aggregation.
  2. Hai phép `DistinctCount` khác cột nguồn (`match_key` để đếm trận và `player_key` để đếm người) **bắt buộc phải nằm ở 2 Measure Group riêng biệt** theo chuẩn khuyến nghị của Microsoft Analysis Services để mỗi độ đo tự xây dựng vùng phân vùng (Partition) và chỉ mục riêng.
  3. Tránh hiện tượng khóa tài nguyên (table lock) trong quá trình xử lý (Process Cube).

---

## 5. Bước 4: Chi tiết 8 Base Measures (Thước đo cơ sở)

| STT | Tên Thước đo | Nhóm (Measure Group) | Phép tính | Cột nguồn | Ý nghĩa nghiệp vụ |
|:---:|---|---|:---:|---|---|
| 1 | `[Thẻ vàng]` | Kỷ luật thi đấu | `SUM` | `yellow_cards` | Tổng số thẻ vàng đã rút ra trong trận đấu/mùa giải. |
| 2 | `[Thẻ đỏ]` | Kỷ luật thi đấu | `SUM` | `red_cards` | Tổng số thẻ đỏ (bao gồm 2 vàng thành đỏ và đỏ trực tiếp). |
| 3 | `[Số phút thi đấu]` | Kỷ luật thi đấu | `SUM` | `minutes_played` | Tổng thời gian thực chiến trên sân của cầu thủ. |
| 4 | `[Lượt ra sân]` | Kỷ luật thi đấu | `SUM` | `appearance_count` | Tổng số lượt thi đấu (mỗi dòng fact tương ứng 1 lượt). |
| 5 | `[Bàn thắng]` | Kỷ luật thi đấu | `SUM` | `goals` | Số bàn thắng ghi được, làm cơ sở đo lường lối chơi cống hiến. |
| 6 | `[Kiến tạo]` | Kỷ luật thi đấu | `SUM` | `assists` | Số đường chuyền thành bàn. |
| 7 | `[Số trận đấu]` | Trận đấu điều hành | `DistinctCount` | `match_key` | Số trận đấu duy nhất (loại bỏ trùng lặp khi nhiều cầu thủ đá cùng 1 trận). |
| 8 | `[Số cầu thủ ra sân]` | Cầu thủ ra sân | `DistinctCount` | `player_key` | Số cá nhân cầu thủ khác nhau thực tế được sử dụng. |

---

## 6. Bước 5: Chi tiết 10 Calculated Members (Thành viên tính toán MDX)

Mọi chỉ số nâng cao được định nghĩa bằng MDX Script trong Cube nhằm đảm bảo dữ liệu tính toán tức thời (on-the-fly) theo bất kỳ góc nhìn phân tích nào:

### 1. `[Tổng thẻ phạt]`
* **Công thức**: `[Measures].[Thẻ vàng] + [Measures].[Thẻ đỏ]`
* **Ý nghĩa**: Đánh giá tổng dung lượng thẻ phạt mà một đội bóng/cầu thủ phải nhận hoặc một trọng tài đã rút ra.

### 2. `[Điểm kỷ luật Fair Play]` (FIFA Disciplinary Standard)
* **Công thức**: `[Measures].[Thẻ vàng] * 1 + [Measures].[Thẻ đỏ] * 3`
* **Ý nghĩa**: Áp dụng đúng chuẩn thang điểm phạt Fair-play của FIFA và ban tổ chức Premier League: mỗi thẻ vàng tính 1 điểm trừ, mỗi thẻ đỏ tính 3 điểm trừ. Điểm kỷ luật càng cao chứng tỏ mức độ bạo lực càng lớn.

### 3. `[Thẻ mỗi trận]`
* **Công thức**: `IIF([Measures].[Số trận đấu] = 0, NULL, [Measures].[Tổng thẻ phạt] / [Measures].[Số trận đấu])`
* **Ý nghĩa**: Thước đo trung bình số thẻ được rút ra trong 1 trận. Đây là chỉ số then chốt để định lượng độ nghiêm khắc của trọng tài và tính căng thẳng của trận đấu.

### 4. `[Thẻ vàng mỗi trận]`
* **Công thức**: `IIF([Measures].[Số trận đấu] = 0, NULL, [Measures].[Thẻ vàng] / [Measures].[Số trận đấu])`
* **Ý nghĩa**: Mức độ cảnh cáo trung bình mỗi trận đấu.

### 5. `[Thẻ đỏ mỗi trận]`
* **Công thức**: `IIF([Measures].[Số trận đấu] = 0, NULL, [Measures].[Thẻ đỏ] / [Measures].[Số trận đấu])`
* **Ý nghĩa**: Tần suất truất quyền thi đấu. Giúp phân biệt trọng tài thích rút thẻ đỏ dằn mặt hay trọng tài chỉ dùng thẻ vàng nhắc nhở.

### 6. `[Điểm kỷ luật mỗi trận]`
* **Công thức**: `IIF([Measures].[Số trận đấu] = 0, NULL, [Measures].[Điểm kỷ luật Fair Play] / [Measures].[Số trận đấu])`
* **Ý nghĩa**: Điểm trừ kỷ luật trung bình theo từng trận của câu lạc bộ, loại bỏ sai lệch về số lượng trận đấu đá nhiều hay ít.

### 7. `[Phút mỗi thẻ vàng]`
* **Công thức**: `IIF([Measures].[Thẻ vàng] = 0, NULL, [Measures].[Số phút thi đấu] / [Measures].[Thẻ vàng])`
* **Ý nghĩa**: Thước đo tần suất phạm lỗi: Cầu thủ hoặc vị trí thi đấu phải mất bao nhiêu phút trên sân thì sẽ nhận 1 thẻ vàng. Giá trị càng nhỏ thể hiện nguy cơ dính thẻ càng cao (phạm lỗi liên tục).

### 8. `[Tỉ lệ thẻ đỏ]`
* **Công thức**: `IIF([Measures].[Tổng thẻ phạt] = 0, NULL, [Measures].[Thẻ đỏ] / [Measures].[Tổng thẻ phạt])`
* **Ý nghĩa**: Tỷ lệ phần trăm thẻ đỏ trong tổng số thẻ phạt. Phản ánh mức độ nghiêm trọng và thô bạo của các pha vào bóng.

### 9. `[Bàn thắng trên mỗi thẻ]` (Goals to Cards Ratio)
* **Công thức**: `IIF([Measures].[Tổng thẻ phạt] = 0, NULL, [Measures].[Bàn thắng] / [Measures].[Tổng thẻ phạt])`
* **Ý nghĩa**: Đo lường tương quan giữa giá trị cống hiến tấn công (bàn thắng) và mức độ bạo lực (thẻ phạt). 
  * Chỉ số $> 1.0$: Đội bóng chơi đẹp mắt, tập trung ghi bàn hơn là phạm lỗi (Ví dụ: Man City, Arsenal, Bayern Munich).
  * Chỉ số $< 0.4$: Đội bóng thiên về phòng ngự tiêu cực, phá lối chơi và chặt chém đối phương.

### 10. `[Thẻ mỗi cầu thủ]`
* **Công thức**: `IIF([Measures].[Số cầu thủ ra sân] = 0, NULL, [Measures].[Tổng thẻ phạt] / [Measures].[Số cầu thủ ra sân])`
* **Ý nghĩa**: Đánh giá sự phân bổ thẻ phạt trong nội bộ đội bóng: thẻ phạt tập trung vào một vài cá nhân cá biệt hay lan rộng khắp toàn bộ đội hình.

---

## 7. Bước 6: Thiết kế 2 Key Performance Indicators (KPIs)

Cube tích hợp **2 KPI chuyên nghiệp** phục vụ giám sát vận hành:

### KPI 1: `Chỉ số Fair Play CLB` (Club Fair Play Index)
* **Mục đích**: Đánh giá mức độ tuân thủ luật thi đấu của Câu lạc bộ.
* **Cấu hình MDX**:
  * **Value**: `[Measures].[Thẻ mỗi trận]`
  * **Goal**: `3.0` (Ngưỡng quy ước chuẩn quốc tế: Mỗi đội bóng không nên nhận quá 3 thẻ/trận).
  * **Status Expression**:
    ```mdx
    Case
      When [Measures].[Thẻ mỗi trận] <= 3.0 Then 1    /* 🟢 Xanh: Tốt (Fair-play) */
      When [Measures].[Thẻ mỗi trận] <= 4.0 Then 0    /* 🟡 Vàng: Chấp nhận được */
      Else -1                                         /* 🔴 Đỏ: Cảnh báo bạo lực */
    End
    ```
  * **Trend Expression**: So sánh với mùa giải trước (`ParallelPeriod` hoặc `PrevMember`). Nếu số thẻ giảm thì xu hướng tốt (`+1`), nếu tăng thì xấu (`-1`).

### KPI 2: `Độ nghiêm khắc Trọng tài` (Referee Strictness Index)
* **Mục đích**: Nhận diện phong cách điều hành của trọng tài để Ban tổ chức phân công bắt các trận cầu nóng (Derby, Chung kết).
* **Cấu hình MDX**:
  * **Value**: `[Measures].[Thẻ mỗi trận]`
  * **Goal**: `4.0` (Ngưỡng trung bình của các trọng tài chuẩn FIFA).
  * **Status Expression**:
    ```mdx
    Case
      When [Measures].[Thẻ mỗi trận] >= 5.0 Then -1   /* 🔴 Rất nghiêm khắc / Thích rút thẻ */
      When [Measures].[Thẻ mỗi trận] >= 3.5 Then 0    /* 🟡 Tiêu chuẩn mực thước */
      Else 1                                          /* 🟢 Nương tay / Thả lỏng trận đấu */
    End
    ```

---

## 8. Bước 7: 8 Câu hỏi Nghiệp vụ & Truy vấn MDX đối chiếu SQL

Mỗi câu hỏi dưới đây giải quyết một bài toán quản trị thực tế, đi kèm cú pháp MDX chuẩn và câu lệnh SQL đối chiếu từ kho dữ liệu.

---

### Q1: Top 10 trọng tài nghiêm khắc nhất thế giới (tối thiểu điều hành 50 trận)?
* **Ý nghĩa**: Lọc ra các trọng tài có xu hướng "rút thẻ nhiều nhất", loại bỏ các trọng tài bắt ít trận để tránh sai lệch thống kê.
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Số trận đấu], 
          [Measures].[Thẻ vàng], 
          [Measures].[Thẻ đỏ], 
          [Measures].[Tổng thẻ phạt], 
          [Measures].[Thẻ mỗi trận]
      } ON 0,
      TOPCOUNT(
          FILTER(
              [Trận đấu].[Trọng tài].[Trọng tài].MEMBERS,
              [Trận đấu].[Trọng tài].CURRENTMEMBER.NAME <> "Không xác định" 
              AND [Measures].[Số trận đấu] >= 50
          ),
          10,
          [Measures].[Thẻ mỗi trận]
      ) ON 1
  FROM [Kỷ luật và Trọng tài];
  ```
* **Giải thích cú pháp MDX**:
  * `ON 0` (Trục COLUMNS): Đặt các thước đo cần phân tích.
  * `ON 1` (Trục ROWS): Trục dòng hiển thị danh sách trọng tài.
  * `FILTER(...)`: Lọc bỏ các trọng tài "Không xác định" và điều kiện `[Số trận đấu] >= 50`.
  * `TOPCOUNT(..., 10, [Thẻ mỗi trận])`: Lấy đúng 10 trọng tài có giá trị `[Thẻ mỗi trận]` cao nhất từ tập hợp đã lọc.
* **SQL đối chiếu**:
  ```sql
  SELECT TOP 10 
      m.referee,
      COUNT(DISTINCT f.match_key) AS so_tran,
      SUM(f.yellow_cards) AS the_vang,
      SUM(f.red_cards) AS the_do,
      SUM(f.yellow_cards + f.red_cards) AS tong_the,
      CAST(SUM(f.yellow_cards + f.red_cards) * 1.0 / NULLIF(COUNT(DISTINCT f.match_key), 0) AS DECIMAL(5,2)) AS the_moi_tran
  FROM fact_player_appearance f
  JOIN dim_match m ON f.match_key = m.match_key
  WHERE m.referee IS NOT NULL AND m.referee <> N'Không xác định'
  GROUP BY m.referee
  HAVING COUNT(DISTINCT f.match_key) >= 50
  ORDER BY the_moi_tran DESC;
  ```
* **Kết quả insight**: Trọng tài José Antonio Teixeira Vitienes dẫn đầu với **6.46 thẻ/trận**, tiếp theo là Dimitrios Styliaras **6.38 thẻ/trận**.

---

### Q2: Cơ cấu thẻ phạt phân bổ theo Vị trí thi đấu trên sân ra sao?
* **Ý nghĩa**: Chỉ ra tuyến thi đấu nào trên sân phải gánh chịu rủi ro thẻ phạt nặng nề nhất.
* **Câu lệnh MDX**:
  ```mdx
  WITH 
  MEMBER [Measures].[Tỉ trọng thẻ] AS
      [Measures].[Tổng thẻ phạt] / ([Measures].[Tổng thẻ phạt], [Cầu thủ].[Vị trí].[All]),
      FORMAT_STRING = "0.0%"
  SELECT 
      {
          [Measures].[Thẻ vàng], 
          [Measures].[Thẻ đỏ], 
          [Measures].[Tổng thẻ phạt], 
          [Measures].[Tỉ trọng thẻ]
      } ON 0,
      EXCEPT(
          [Cầu thủ].[Vị trí].[Vị trí].MEMBERS,
          {[Cầu thủ].[Vị trí].[Không xác định], [Cầu thủ].[Vị trí].[Missing]}
      ) ON 1
  FROM [Kỷ luật và Trọng tài];
  ```
* **Giải thích cú pháp MDX**:
  * `WITH MEMBER [Tỉ trọng thẻ]`: Tạo thành viên tính toán tạm thời lấy số thẻ vị trí hiện tại chia cho tổng thẻ của cấp `[All]` (tất cả vị trí).
  * `EXCEPT(...)`: Loại trừ các giá trị lỗi dữ liệu như "Không xác định", "Missing".
* **SQL đối chiếu**:
  ```sql
  SELECT 
      p.position,
      SUM(f.yellow_cards) AS the_vang,
      SUM(f.red_cards) AS the_do,
      SUM(f.yellow_cards + f.red_cards) AS tong_the,
      CAST(SUM(f.yellow_cards + f.red_cards) * 100.0 / SUM(SUM(f.yellow_cards + f.red_cards)) OVER() AS DECIMAL(5,1)) AS ti_trong_pct
  FROM fact_player_appearance f
  JOIN dim_player p ON f.player_key = p.player_key
  WHERE p.position NOT IN (N'Không xác định', N'Missing')
  GROUP BY p.position
  ORDER BY tong_the DESC;
  ```
* **Kết quả insight**: Tuyến Hậu vệ (**Defender**) gánh **40.8%** tổng thẻ, Tiền vệ (**Midfield**) chiếm **35.2%**, Tiền đạo (**Attack**) chiếm **21.1%**, Thủ môn (**Goalkeeper**) chỉ chiếm **2.8%**.

---

### Q3: CLB nào chơi bạo lực nhất (Điểm Fair-play cao nhất) tại Ngoại Hạng Anh mùa 2024/25?
* **Ý nghĩa**: Bảng xếp hạng bạo lực của giải đấu cấp cao nhất nước Anh theo thang điểm trừ của FIFA.
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Thẻ vàng], 
          [Measures].[Thẻ đỏ], 
          [Measures].[Tổng thẻ phạt], 
          [Measures].[Điểm kỷ luật Fair Play]
      } ON 0,
      TOPCOUNT(
          [CLB].[CLB].[CLB].MEMBERS,
          5,
          [Measures].[Điểm kỷ luật Fair Play]
      ) ON 1
  FROM [Kỷ luật và Trọng tài]
  WHERE (
      [Giải đấu].[Mã giải].[GB1],
      [Mùa giải].[Mùa giải].[2024/25]
  );
  ```
* **Giải thích cú pháp MDX**:
  * `WHERE (...)`: Áp dụng kỹ thuật Slice (Cắt lát) chỉ xét riêng giải đấu Premier League (`Mã giải: GB1`) và mùa bóng `2024/25`.
  * `TOPCOUNT(..., 5, [Điểm kỷ luật Fair Play])`: Chọn ra 5 CLB có điểm trừ kỷ luật cao nhất.
* **SQL đối chiếu**:
  ```sql
  SELECT TOP 5 
      c.club_name,
      SUM(f.yellow_cards) AS the_vang,
      SUM(f.red_cards) AS the_do,
      SUM(f.yellow_cards + f.red_cards) AS tong_the,
      SUM(f.yellow_cards * 1 + f.red_cards * 3) AS diem_fair_play
  FROM fact_player_appearance f
  JOIN dim_club c ON f.club_key = c.club_key
  JOIN dim_competition comp ON f.competition_key = comp.competition_key
  JOIN dim_season s ON f.season_key = s.season_key
  WHERE comp.competition_code = 'GB1' AND s.season_label = '2024/25'
  GROUP BY c.club_name
  ORDER BY diem_fair_play DESC;
  ```
* **Kết quả insight**: Bournemouth đứng đầu danh sách nhận án phạt (**105 điểm** - 96 vàng, 3 đỏ), kế tiếp là Chelsea (**104 điểm** - 101 vàng, 1 đỏ), Southampton (**98 điểm**).

---

### Q4: Đội bóng nào thi đấu cống hiến nhất (Tỉ số Bàn thắng trên mỗi thẻ phạt cao nhất)?
* **Ý nghĩa**: Tìm ra các đại diện tiêu biểu cho trường phái "bóng đá đẹp" (nhiều bàn thắng, ít thẻ phạt) mùa giải 2024/25.
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Bàn thắng], 
          [Measures].[Tổng thẻ phạt], 
          [Measures].[Bàn thắng trên mỗi thẻ]
      } ON 0,
      TOPCOUNT(
          FILTER(
              [CLB].[CLB].[CLB].MEMBERS,
              [Measures].[Số trận đấu] >= 30
          ),
          10,
          [Measures].[Bàn thắng trên mỗi thẻ]
      ) ON 1
  FROM [Kỷ luật và Trọng tài]
  WHERE ([Mùa giải].[Mùa giải].[2024/25]);
  ```
* **Giải thích cú pháp MDX**: Lọc các đội đá tối thiểu 30 trận để có ý nghĩa thống kê mùa giải trọn vẹn, sắp xếp giảm dần theo thước đo `[Bàn thắng trên mỗi thẻ]`.

---

### Q5: So sánh xu hướng thẻ phạt theo Phân cấp Địa lý (Liên đoàn UEFA $\rightarrow$ Quốc gia)?
* **Ý nghĩa**: Minh họa thao tác **Drill-down** trong OLAP từ cấp châu lục xuống các giải vô địch quốc gia thành viên.
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Số trận đấu], 
          [Measures].[Tổng thẻ phạt], 
          [Measures].[Thẻ mỗi trận]
      } ON 0,
      ORDER(
          [Giải đấu].[Liên đoàn - Quốc gia - Giải đấu].[Liên đoàn].[UEFA].CHILDREN,
          [Measures].[Thẻ mỗi trận],
          BDESC
      ) ON 1
  FROM [Kỷ luật và Trọng tài]
  WHERE ([Mùa giải].[Mùa giải].[2024/25]);
  ```
* **Giải thích cú pháp MDX**: `.CHILDREN` lấy danh sách các Quốc gia trực thuộc Liên đoàn UEFA; `BDESC` sắp xếp giảm dần độc lập (Break Hierarchy).

---

### Q6: Tính chất vòng đấu (Knock-out loại trực tiếp vs Vòng bảng Matchday) ảnh hưởng thế nào đến thẻ phạt?
* **Ý nghĩa**: Kiểm chứng giả thuyết: Các trận cầu knock-out một mất một còn có quyết liệt và nhận nhiều thẻ phạt hơn vòng đấu bảng thông thường hay không?
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Số trận đấu], 
          [Measures].[Thẻ vàng], 
          [Measures].[Thẻ đỏ], 
          [Measures].[Thẻ mỗi trận]
      } ON 0,
      [Trận đấu].[Loại vòng].[Loại vòng].MEMBERS ON 1
  FROM [Kỷ luật và Trọng tài]
  WHERE ([Mùa giải].[Mùa giải].[2024/25]);
  ```

---

### Q7: Tần suất nhận thẻ theo vị trí thi đấu (Bao nhiêu phút trên sân thì dính 1 thẻ vàng)?
* **Ý nghĩa**: Cung cấp insight thể lực và chiến thuật cho HLV: Vị trí nào cần có phương án thay người sớm để tránh nguy cơ thẻ vàng thứ hai.
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Số phút thi đấu], 
          [Measures].[Thẻ vàng], 
          [Measures].[Phút mỗi thẻ vàng]
      } ON 0,
      EXCEPT(
          [Cầu thủ].[Vị trí].[Vị trí].MEMBERS,
          {[Cầu thủ].[Vị trí].[Không xác định], [Cầu thủ].[Vị trí].[Missing]}
      ) ON 1
  FROM [Kỷ luật và Trọng tài];
  ```
* **Kết quả insight**: Vị trí Hậu vệ trung bình chỉ mất **560 phút** (khoảng 6 trận) là dính 1 thẻ vàng, trong khi Thủ môn phải mất tới hơn **3.200 phút** (khoảng 35 trận).

---

### Q8: Trọng tài nào có tỉ lệ rút thẻ đỏ cao nhất (nguy hiểm nhất cho các cầu thủ)?
* **Ý nghĩa**: Cảnh báo ban huấn luyện về các "hung thần thẻ đỏ" để dặn dò cầu thủ tuyệt đối tránh các pha phạm lỗi mạo hiểm.
* **Câu lệnh MDX**:
  ```mdx
  SELECT 
      {
          [Measures].[Số trận đấu], 
          [Measures].[Thẻ đỏ], 
          [Measures].[Thẻ đỏ mỗi trận], 
          [Measures].[Tỉ lệ thẻ đỏ]
      } ON 0,
      TOPCOUNT(
          FILTER(
              [Trận đấu].[Trọng tài].[Trọng tài].MEMBERS,
              [Trận đấu].[Trọng tài].CURRENTMEMBER.NAME <> "Không xác định" 
              AND [Measures].[Số trận đấu] >= 50
          ),
          10,
          [Measures].[Thẻ đỏ mỗi trận]
      ) ON 1
  FROM [Kỷ luật và Trọng tài];
  ```

---

## 9. Bước 8: Minh họa 5 Thao tác OLAP Kinh điển trên Cube

Khi vấn đáp, giảng viên thường yêu cầu sinh viên thao tác trực tiếp trên Cube Browser của Visual Studio hoặc SSMS. Bảng dưới đây tóm tắt cách thực hiện:

| Thao tác OLAP | Thao tác thực tế trên Cube Browser / SSMS | Câu lệnh MDX / Hành động | Ý nghĩa thực tiễn |
|---|---|---|---|
| **Roll-up** *(Thu gộp)* | Thu nhỏ từ chi tiết Cầu thủ $\rightarrow$ Vị trí $\rightarrow$ Toàn bộ vị trí | Kéo thuộc tính `Vị trí` thay cho `Cầu thủ` | Xem bức tranh tổng thể thẻ phạt phân bố theo các tuyến chiến thuật trên sân thay vì xem từng cá nhân rời rạc. |
| **Drill-down** *(Khoan sâu)* | Mở rộng từ `Liên đoàn: UEFA` $\rightarrow$ `Quốc gia: England` $\rightarrow$ `Giải đấu: Premier League` | Nhấp vào dấu `+` trên Hierarchy `Liên đoàn - Quốc gia - Giải đấu` | Tìm ra giải đấu nào tại châu Âu đang có tình trạng thi đấu bạo lực nhất. |
| **Slice** *(Cắt lát)* | Đặt bộ lọc cố định cho 1 mùa giải cụ thể | Kéo `[Mùa giải].[Mùa giải].[2024/25]` vào vùng Filter (mục `WHERE`) | Cô lập dữ liệu để đánh giá công tác kỷ luật riêng trong mùa bóng hiện tại. |
| **Dice** *(Cắt khối)* | Lọc kết hợp đa chiều: Top 5 giải đấu $\times$ Nhóm Hậu vệ $\times$ Mùa 2024/25 | `WHERE ([Mã giải].[GB1], [Vị trí].[Defender], [Mùa giải].[2024/25])` | Khảo sát sâu phân khúc đối tượng cụ thể (hậu vệ tại giải Ngoại Hạng Anh năm nay). |
| **Pivot** *(Xoay chiều)* | Chuyển chiều `Vị trí` từ trục Dòng (Rows) sang trục Cột (Columns) và ngược lại | Hoán đổi vị trí giữa trục Rows và Columns | Đổi góc nhìn trực quan để phát hiện xu hướng phân bổ thẻ qua các chiều phân tích. |

---

## 10. Cẩm nang Vấn đáp: Bộ Câu hỏi Giảng viên & Kịch bản Trả lời Chuẩn điểm A+

### Câu hỏi 1: "Tại sao em lại tách thành 3 Measure Group thay vì để chung trong 1 Measure Group?"
> **Kịch bản trả lời**: 
> "Thưa Thầy/Cô, việc tách 3 Measure Group xuất phát từ chuẩn thiết kế hiệu năng cao của SSAS Multidimensional:
> 1. Nhóm `Kỷ luật thi đấu` sử dụng hàm cộng gộp thông thường `SUM`, lưu trữ theo cơ chế nén MOLAP tiêu chuẩn.
> 2. Hai nhóm `Trận đấu điều hành` và `Cầu thủ ra sân` sử dụng hàm **`DistinctCount`** trên `match_key` và `player_key`. Thuật toán Distinct Count yêu cầu SSAS tạo chỉ mục bitmap riêng biệt để loại trùng lặp khi tổng hợp dữ liệu.
> 3. Nếu gộp chung vào 1 Measure Group, hiệu năng tính toán sẽ bị suy giảm nghiêm trọng và SSAS sẽ đưa ra cảnh báo vi phạm Best Practice. Việc tách riêng giúp tối ưu hóa dung lượng lưu trữ, cho phép xử lý song song (parallel processing) và đảm bảo thời gian truy vấn nhanh nhất."

### Câu hỏi 2: "Điểm kỷ luật Fair Play được tính như thế nào? Có cơ sở thực tế không?"
> **Kịch bản trả lời**: 
> "Dạ thưa Thầy/Cô, điểm kỷ luật Fair Play được em tính toán bằng Calculated Member theo chuẩn quy định của FIFA và Ban tổ chức Premier League:
> `Điểm Fair Play = (Thẻ vàng * 1) + (Thẻ đỏ * 3)`.
> Điểm số này đo lường mức độ vi phạm luật thi đấu: 1 thẻ đỏ tương đương với 3 lần phạm lỗi thẻ vàng. Điểm càng cao thì đội bóng chơi càng thiếu kỷ luật."

### Câu hỏi 3: "Sự khác biệt lớn nhất giữa việc viết truy vấn bằng MDX trên SSAS Cube so với viết bằng T-SQL trong SQL Server là gì?"
> **Kịch bản trả lời**: 
> "Thưa Thầy/Cô, có 3 khác biệt căn bản:
> 1. **Về cấu trúc đa chiều**: SQL trả về kết quả dạng bảng phẳng 2 chiều (Row/Column), trong khi MDX cho phép truy vấn trực tiếp trên không gian đa chiều (Multidimensional axes: ON COLUMNS, ON ROWS, ON PAGES, ON SLICES).
> 2. **Về tốc độ tính toán**: T-SQL phải quét qua hàng triệu dòng bảng Fact và thực hiện nhiều phép JOIN nặng nề. Trong khi đó, Cube SSAS đã tính toán và tổng hợp sẵn (Pre-aggregated MOLAP) nên câu truy vấn MDX trả về kết quả gần như tức thì (dưới 1 giây).
> 3. **Về khả năng hỗ trợ Business Analytics**: MDX tích hợp sẵn các hàm chuyên sâu về thứ bậc (Hierarchy navigation như `.PARENT`, `.CHILDREN`, `.MEMBERS`), các hàm phân tích xu hướng thời gian (`ParallelPeriod`), và hỗ trợ trực tiếp KPI (Value, Goal, Status, Trend) mà SQL truyền thống rất phức tạp mới viết được."

### Câu hỏi 4: "Chỉ số `[Bàn thắng trên mỗi thẻ]` có ý nghĩa gì đối với ban lãnh đạo đội bóng?"
> **Kịch bản trả lời**: 
> "Dạ thưa Thầy/Cô, đây là chỉ số đo lường phong cách bóng đá (Lối chơi cống hiến vs Lối chơi thể lực). Nếu tỷ số này $> 1.0$, nghĩa là đội bóng ghi được nhiều bàn thắng hơn số thẻ phải nhận (tiêu biểu như Man City hay Arsenal), thể hiện đội bóng kiểm soát thế trận và thi đấu hoa mỹ. Ngược lại, nếu tỷ số $< 0.4$, đội bóng đang phải dùng nhiều pha phạm lỗi để ngăn chặn đối phương nhưng lại ghi được rất ít bàn thắng, đây là tín hiệu báo động về mặt chiến thuật cần điều chỉnh."
