# Giai đoạn mới: SSAS + Power BI

> Khung SSAS đã dựng xong và chạy thử với dữ liệu thật: cube ra đúng số liệu như SQL (Liverpool 84 điểm, Salah 29 bàn). Mọi người nhận phần, tạo cube riêng cho phần mình rồi điền tiếp, giống cách làm SSIS.

## 1. Bốn phần việc

Mỗi người nhận 1 phần và báo tên phần vào nhóm.

| Phần | Nội dung | Cube riêng phải tạo | Dimension phải điền | File hướng dẫn |
|---|---|---|---|---|
| **1. Hiệu suất đội bóng và HLV** | Fact_Team_Match: bảng xếp hạng, tỉ lệ thắng, lợi thế sân nhà, sạch lưới | **Hiệu suất đội bóng** | Giải đấu, Trận đấu, HLV, CLB | [Phan_1_Hieu_suat_doi_bong.md](context/Phan_1_Hieu_suat_doi_bong.md) |
| **2. Hiệu suất cầu thủ** | Fact_Player_Appearance: vua phá lưới, bàn mỗi 90 phút, trọng tài. Thêm việc gộp bảng đối chiếu cube = SQL của cả nhóm | **Hiệu suất cầu thủ** | – | [Phan_2_Hieu_suat_cau_thu.md](context/Phan_2_Hieu_suat_cau_thu.md) |
| **3. Giá trị cầu thủ và chuyển nhượng** | Fact_Player_Valuation + Fact_Transfer: giá trị đội hình, chi tiêu ròng, phí chênh, thương vụ đội trẻ | **Thị trường cầu thủ** (✅ đã xong, dùng làm mẫu) | Loại chuyển nhượng, Cầu thủ, Tuổi (✅ đã xong) | [Phan_3_Gia_tri_va_chuyen_nhuong.md](context/Phan_3_Gia_tri_va_chuyen_nhuong.md) |
| **4. Power BI** | Toàn bộ báo cáo Power BI, live connection vào cube của từng phần, không làm SSAS. Trong lúc chờ cube có thể làm nháp bằng Import thẳng từ kho | – | – | [Phan_4_PowerBI.md](context/Phan_4_PowerBI.md) |

**Mỗi phần tạo một cube riêng.** Không dồn hết vào cube `Football DWH`. Cube của phần nào chỉ chứa fact và dimension của phần đó, và phải ghi rõ **giá trị mang lại** (trả lời câu hỏi gì, hỗ trợ quyết định gì) trong Description của cube. Cách tạo xem mục C trong file context, phần *Mỗi phần tạo một cube riêng*. Cube `Thị trường cầu thủ` của Phần 3 là mẫu đầy đủ.

Mỗi file hướng dẫn có đủ:
- cột của kho;
- câu hỏi nghiệp vụ;
- measure cần làm và KPI;
- 5 thao tác OLAP;
- SQL đối chiếu mẫu;
- các lỗi dễ gặp.

Có thể dán nguyên file vào ChatGPT / Claude để được hướng dẫn từng bước.

## 2. Chuẩn bị

Ai làm SSAS cũng phải làm phần này, mỗi máy làm 1 lần.

1. Chạy `git pull` trên `main`.
2. Cài Visual Studio và extension **Microsoft Analysis Services Projects**. SQL Server phải có **Analysis Services** chạy ở chế độ **Multidimensional**.
3. Cấp quyền cho SSAS đọc kho. `sql/01_create_dw.sql` đã có đoạn tự cấp quyền ở cuối file, nên chạy lại `00` → `01` là có quyền. Chỉ khi chưa chạy lại 2 script đó thì mới mở SSMS, kết nối **Database Engine** và chạy tay:

   ```sql
   USE football_dwh_dw;
   CREATE USER [NT SERVICE\MSSQLServerOLAPService] FOR LOGIN [NT SERVICE\MSSQLServerOLAPService];
   ALTER ROLE db_datareader ADD MEMBER [NT SERVICE\MSSQLServerOLAPService];
   ```

   Nếu báo chưa có login thì chạy câu này trước:

   ```sql
   CREATE LOGIN [NT SERVICE\MSSQLServerOLAPService] FROM WINDOWS;
   ```

4. Mở `ssas-transfermarkt/Football_DAWH_SSAS/Football_DAWH_SSAS.slnx`, rồi chuột phải project → **Deploy**.
5. Mở cube → tab **Browser**. Kéo *Điểm* và *CLB* vào, lọc Giải đấu = premier-league, Mùa giải = 2024/25. **Liverpool = 84** là OK.

> ⚠️ Nếu SQL Server trên máy không phải `localhost` (ví dụ `MSI\TRIEUHIEU`), sửa Server trong `Football DWH.ds` trên máy mình. **Không commit** thay đổi này.

## 3. Khung đã có sẵn (không cần làm lại)

| Thành phần | Trạng thái |
|---|---|
| Data Source, DSV | Đủ 12 bảng và các cột tính sẵn (`home_win`, `fee_disclosed`, `pro_age`, …) |
| Dim **Ngày** (Năm → Quý → Tháng → Ngày), **Mùa giải** | Đã điền đủ |
| Dim **Loại chuyển nhượng**, **Cầu thủ** (Vị trí → Vị trí chi tiết → Cầu thủ), **Tuổi** | Đã điền đủ (Phần 3) |
| Dim Giải đấu, Trận đấu, HLV, CLB | Mới có khóa và tên. Phần 1 điền attribute, hierarchy |
| Cube tổng `Football DWH` | 5 measure group, measure gốc, role-playing. **Giữ nguyên**, dùng để kiểm tra số liệu và làm trang Tổng quan. Không viết MDX / KPI vào cube này |
| Cube `Thị trường cầu thủ` | Xong (Phần 3): 2 measure group, 9 dim, 12 calculated member, 1 KPI, đã khớp SQL |

## 4. Quy tắc để không đè file của nhau

- **File `.dim`:** mỗi dim là 1 file riêng, ai sửa dim của người nấy thì không lo xung đột.
- **File `.cube`:** mỗi phần có cube riêng (file riêng), ai sửa cube của người nấy.
- **File `.dsv` là file dùng chung và không merge được.** Muốn sửa thì làm theo thứ tự:
  1. Nhắn nhóm **"đang giữ DSV"**.
  2. `git pull`.
  3. Sửa → Deploy → kiểm tra.
  4. Commit + push ngay.
  5. Nhắn **"trả DSV"**.

  ❌ Không để 2 người sửa DSV cùng lúc.
- Cần thêm cột tính trong DSV thì nhắn trong nhóm, đừng tự sửa lúc người khác đang giữ.
- Không commit file `.user`, thư mục `bin/` / `obj/`, hay tên server riêng của máy mình.

## 5. Thứ tự làm

| Giai đoạn | Phần 1–3 | Phần 4 |
|---|---|---|
| 1 | Điền dim; viết câu hỏi, SQL đối chiếu, nháp MDX | Làm layout Power BI |
| 2 | Tạo cube riêng, viết MDX / KPI vào cube của mình, kiểm tra cube = SQL, chụp 5 thao tác OLAP | Dựng các trang Power BI (mỗi trang 1 file `.pbix` live vào cube tương ứng) |
| 3 | Chụp ảnh minh chứng, viết phần báo cáo; Phần 2 gộp bảng đối chiếu | Hoàn thiện Power BI |

## 6. Khi nào là xong

- Measure của phần mình trên cube **khớp với SQL đối chiếu**.
- Có ảnh 5 thao tác OLAP (Phần 4: ảnh các trang Power BI).
- Có đoạn viết cho báo cáo: câu hỏi → measure → kết quả → ý nghĩa.

Kẹt chỗ nào cứ chụp màn hình gửi lên nhóm.
