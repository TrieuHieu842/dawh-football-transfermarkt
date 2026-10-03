/* =====================================================================
   01_create_dw.sql
   Tạo kho dữ liệu football_dwh_dw theo tài liệu thiết kế (mục 5, 6, 7.3).
   Chỉ gồm các thuộc tính / measure đã chọn lọc trong thiết kế:
   mỗi cột đều có nguồn và có ý nghĩa phân tích ở ít nhất một chiều.
   - 8 dimension (có dòng Unknown key = -1)
   - 4 fact gốc + 2 fact tổng hợp
   - Dim_Date, Dim_Season, Dim_Transfer_Type được sinh sẵn (bảng tĩnh)
   - etl_load_window, etl_batch: cửa sổ nạp gia tăng và nhật ký mỗi lần chạy
   Cột batch_id là cột kỹ thuật để truy vết, không thuộc mô hình phân tích.
   Chạy lại được: các bảng cũ sẽ bị DROP.
   ===================================================================== */
IF DB_ID(N'football_dwh_dw') IS NULL CREATE DATABASE football_dwh_dw;
GO
USE football_dwh_dw;
GO

/* ---------- Xóa theo thứ tự phụ thuộc (fact trước, dimension sau) ---------- */
DROP TABLE IF EXISTS dbo.fact_club_season_summary;
DROP TABLE IF EXISTS dbo.fact_player_season_summary;
DROP TABLE IF EXISTS dbo.fact_transfer;
DROP TABLE IF EXISTS dbo.fact_player_valuation;
DROP TABLE IF EXISTS dbo.fact_player_appearance;
DROP TABLE IF EXISTS dbo.fact_team_match;
DROP TABLE IF EXISTS dbo.dim_transfer_type;
DROP TABLE IF EXISTS dbo.dim_manager;
DROP TABLE IF EXISTS dbo.dim_match;
DROP TABLE IF EXISTS dbo.dim_player;
DROP TABLE IF EXISTS dbo.dim_club;
DROP TABLE IF EXISTS dbo.dim_competition;
DROP TABLE IF EXISTS dbo.dim_season;
DROP TABLE IF EXISTS dbo.dim_date;
DROP TABLE IF EXISTS dbo.etl_batch;
DROP TABLE IF EXISTS dbo.etl_load_window;
GO

/* =====================================================================
   DIMENSION
   ===================================================================== */

/* ---------- 5.1 Dim_Date (tĩnh, 1990-2030) ---------- */
CREATE TABLE dbo.dim_date
(
    date_key        INT           NOT NULL PRIMARY KEY,   -- YYYYMMDD
    full_date       DATE          NULL,
    day_of_week     TINYINT       NOT NULL,               -- 1 = Monday ... 7 = Sunday
    day_name        NVARCHAR(10)  NOT NULL,
    is_weekend      BIT           NOT NULL,
    [month]         TINYINT       NOT NULL,
    month_name      NVARCHAR(10)  NOT NULL,
    [quarter]       TINYINT       NOT NULL,
    [year]          SMALLINT      NOT NULL,
    is_future_date  BIT           NOT NULL                -- so với ngày nạp; cập nhật lại mỗi lần chạy ETL
);
GO

/* ---------- 5.2 Dim_Season (tĩnh) ---------- */
CREATE TABLE dbo.dim_season
(
    season_key         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    season_start_year  SMALLINT      NOT NULL UNIQUE,      -- games.season
    season_label       NVARCHAR(10)  NOT NULL,             -- 2024/25
    season_short       NVARCHAR(10)  NOT NULL              -- 24/25 (transfers.transfer_season)
);
GO

/* ---------- 5.3 Dim_Competition (SCD1) ---------- */
CREATE TABLE dbo.dim_competition
(
    competition_key       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    competition_id        NVARCHAR(20)  NOT NULL UNIQUE,
    competition_name      NVARCHAR(200) NOT NULL,
    competition_type      NVARCHAR(50)  NOT NULL,
    competition_sub_type  NVARCHAR(50)  NOT NULL,
    country_name          NVARCHAR(100) NOT NULL,
    confederation         NVARCHAR(20)  NOT NULL,
    batch_id              NVARCHAR(30)  NULL
);
GO

/* ---------- 5.4 Dim_Club (SCD1 + SCD2 + SCD3) ---------- */
CREATE TABLE dbo.dim_club
(
    club_key               INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    club_id                INT           NOT NULL,
    club_name              NVARCHAR(200) NOT NULL,         -- SCD1
    club_type              NVARCHAR(20)  NOT NULL,         -- SCD1: Club | National Team | Other
    country_name           NVARCHAR(100) NOT NULL,         -- SCD1
    confederation          NVARCHAR(20)  NOT NULL,         -- SCD1
    current_league_id      NVARCHAR(20)  NULL,             -- SCD3
    current_league_name    NVARCHAR(200) NOT NULL,         -- SCD3
    previous_league_name   NVARCHAR(200) NULL,             -- SCD3
    stadium_name           NVARCHAR(200) NOT NULL,         -- SCD2
    stadium_capacity_band  NVARCHAR(30)  NOT NULL,         -- SCD2
    effective_date         DATE          NOT NULL DEFAULT ('1900-01-01'),
    expiry_date            DATE          NOT NULL DEFAULT ('9999-12-31'),
    is_current             BIT           NOT NULL DEFAULT (1),
    batch_id               NVARCHAR(30)  NULL
);
CREATE INDEX ix_dim_club_nk ON dbo.dim_club (club_id, is_current) INCLUDE (effective_date, expiry_date);
GO

/* ---------- 5.5 Dim_Player (SCD1 + SCD2) ---------- */
CREATE TABLE dbo.dim_player
(
    player_key               INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    player_id                INT           NOT NULL,
    full_name                NVARCHAR(200) NOT NULL,       -- SCD1
    date_of_birth            DATE          NULL,           -- SCD1
    country_of_birth         NVARCHAR(100) NOT NULL,       -- SCD1
    citizenship              NVARCHAR(100) NOT NULL,       -- SCD1
    position                 NVARCHAR(50)  NOT NULL,       -- SCD2
    sub_position             NVARCHAR(50)  NOT NULL,       -- SCD2
    foot                     NVARCHAR(20)  NOT NULL,       -- SCD1
    height_band              NVARCHAR(30)  NOT NULL,       -- SCD1
    agent_name               NVARCHAR(200) NOT NULL,       -- SCD2
    contract_expiry_year     SMALLINT      NULL,           -- SCD1
    international_caps_band  NVARCHAR(30)  NOT NULL,       -- SCD1
    effective_date           DATE          NOT NULL DEFAULT ('1900-01-01'),
    expiry_date              DATE          NOT NULL DEFAULT ('9999-12-31'),
    is_current               BIT           NOT NULL DEFAULT (1),
    batch_id                 NVARCHAR(30)  NULL
);
CREATE INDEX ix_dim_player_nk ON dbo.dim_player (player_id, is_current) INCLUDE (effective_date, expiry_date);
GO

/* ---------- 5.6 Dim_Match (SCD1) ---------- */
CREATE TABLE dbo.dim_match
(
    match_key        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    game_id          INT           NOT NULL UNIQUE,
    [round]          NVARCHAR(100) NOT NULL,
    round_type       NVARCHAR(20)  NOT NULL,
    stadium          NVARCHAR(200) NOT NULL,
    referee          NVARCHAR(200) NOT NULL,
    home_formation   NVARCHAR(30)  NOT NULL,
    away_formation   NVARCHAR(30)  NOT NULL,
    attendance_band  NVARCHAR(30)  NOT NULL,
    batch_id         NVARCHAR(30)  NULL
);
GO

/* ---------- 5.7 Dim_Manager (SCD1) ---------- */
CREATE TABLE dbo.dim_manager
(
    manager_key   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    manager_name  NVARCHAR(200) COLLATE Latin1_General_CS_AS NOT NULL UNIQUE,  -- phân biệt hoa thường giống SSIS Lookup
    batch_id      NVARCHAR(30)  NULL
);
GO

/* ---------- 5.8 Dim_Transfer_Type (junk, tĩnh) ---------- */
CREATE TABLE dbo.dim_transfer_type
(
    transfer_type_key  INT           NOT NULL PRIMARY KEY,
    fee_status         NVARCHAR(40)  NOT NULL,
    fee_band           NVARCHAR(30)  NOT NULL,
    CONSTRAINT uq_transfer_type UNIQUE (fee_status, fee_band)
);
GO

/* =====================================================================
   FACT
   Cờ 0/1 dùng TINYINT để SUM trực tiếp ra số trận (measure additive).
   ===================================================================== */

/* ---------- 6.1 Fact_Team_Match: 1 đội trong 1 trận ---------- */
CREATE TABLE dbo.fact_team_match
(
    date_key              INT      NOT NULL REFERENCES dbo.dim_date (date_key),
    season_key            INT      NOT NULL REFERENCES dbo.dim_season (season_key),
    competition_key       INT      NOT NULL REFERENCES dbo.dim_competition (competition_key),
    match_key             INT      NOT NULL REFERENCES dbo.dim_match (match_key),
    club_key              INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    opponent_club_key     INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    manager_key           INT      NOT NULL REFERENCES dbo.dim_manager (manager_key),
    opponent_manager_key  INT      NOT NULL REFERENCES dbo.dim_manager (manager_key),
    is_home               TINYINT  NOT NULL,     -- degenerate
    goals_for             SMALLINT NOT NULL,
    goals_against         SMALLINT NOT NULL,
    is_win                TINYINT  NOT NULL,
    is_draw               TINYINT  NOT NULL,
    is_loss               TINYINT  NOT NULL,
    is_clean_sheet        TINYINT  NOT NULL,
    league_position       SMALLINT NULL,         -- non-additive
    batch_id              NVARCHAR(30) NULL,
    CONSTRAINT pk_fact_team_match PRIMARY KEY (match_key, club_key)
);
GO

/* ---------- 6.2 Fact_Player_Appearance: 1 cầu thủ ra sân trong 1 trận ---------- */
CREATE TABLE dbo.fact_player_appearance
(
    date_key          INT          NOT NULL REFERENCES dbo.dim_date (date_key),
    season_key        INT          NOT NULL REFERENCES dbo.dim_season (season_key),
    competition_key   INT          NOT NULL REFERENCES dbo.dim_competition (competition_key),
    match_key         INT          NOT NULL REFERENCES dbo.dim_match (match_key),
    player_key        INT          NOT NULL REFERENCES dbo.dim_player (player_key),
    club_key          INT          NOT NULL REFERENCES dbo.dim_club (club_key),
    appearance_id     NVARCHAR(50) NOT NULL,     -- degenerate, khóa tự nhiên để nạp gia tăng
    minutes_played    SMALLINT     NOT NULL,
    goals             SMALLINT     NOT NULL,
    assists           SMALLINT     NOT NULL,
    yellow_cards      SMALLINT     NOT NULL,
    red_cards         SMALLINT     NOT NULL,
    appearance_count  TINYINT      NOT NULL DEFAULT (1),
    batch_id          NVARCHAR(30) NULL,
    CONSTRAINT pk_fact_player_appearance PRIMARY KEY (appearance_id)
);
CREATE INDEX ix_fpa_season_player ON dbo.fact_player_appearance (season_key, player_key);
CREATE INDEX ix_fpa_comp_season   ON dbo.fact_player_appearance (competition_key, season_key);
GO

/* ---------- 6.3 Fact_Player_Valuation: 1 lần định giá (periodic snapshot) ---------- */
CREATE TABLE dbo.fact_player_valuation
(
    date_key          INT      NOT NULL REFERENCES dbo.dim_date (date_key),
    player_key        INT      NOT NULL REFERENCES dbo.dim_player (player_key),
    club_key          INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    competition_key   INT      NOT NULL REFERENCES dbo.dim_competition (competition_key),
    market_value_eur  BIGINT   NULL,              -- semi-additive
    value_change_eur  BIGINT   NULL,              -- lần định giá đầu: NULL
    age_at_valuation  TINYINT  NULL,              -- non-additive
    valuation_count   TINYINT  NOT NULL DEFAULT (1),
    batch_id          NVARCHAR(30) NULL,
    CONSTRAINT pk_fact_player_valuation PRIMARY KEY (player_key, date_key)
);
GO

/* ---------- 6.4 Fact_Transfer: 1 lần chuyển nhượng ---------- */
CREATE TABLE dbo.fact_transfer
(
    date_key           INT      NOT NULL REFERENCES dbo.dim_date (date_key),
    season_key         INT      NOT NULL REFERENCES dbo.dim_season (season_key),
    player_key         INT      NOT NULL REFERENCES dbo.dim_player (player_key),
    from_club_key      INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    to_club_key        INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    transfer_type_key  INT      NOT NULL REFERENCES dbo.dim_transfer_type (transfer_type_key),
    transfer_fee_eur   BIGINT   NULL,             -- NULL = không công bố (khác 0)
    market_value_eur   BIGINT   NULL,             -- semi-additive
    fee_premium_eur    BIGINT   NULL,
    age_at_transfer    TINYINT  NULL,             -- non-additive
    transfer_count     TINYINT  NOT NULL DEFAULT (1),
    batch_id           NVARCHAR(30) NULL
);
CREATE INDEX ix_ft_nk          ON dbo.fact_transfer (player_key, date_key, from_club_key, to_club_key);
CREATE INDEX ix_ft_season_to   ON dbo.fact_transfer (season_key, to_club_key);
CREATE INDEX ix_ft_season_from ON dbo.fact_transfer (season_key, from_club_key);
GO

/* ---------- 7.3 Fact tổng hợp theo mùa ---------- */
CREATE TABLE dbo.fact_player_season_summary
(
    player_key       INT      NOT NULL REFERENCES dbo.dim_player (player_key),
    club_key         INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    competition_key  INT      NOT NULL REFERENCES dbo.dim_competition (competition_key),
    season_key       INT      NOT NULL REFERENCES dbo.dim_season (season_key),
    matches_played   INT      NOT NULL,
    minutes_played   INT      NOT NULL,
    goals            INT      NOT NULL,
    assists          INT      NOT NULL,
    yellow_cards     INT      NOT NULL,
    red_cards        INT      NOT NULL,
    batch_id         NVARCHAR(30) NULL,
    CONSTRAINT pk_fact_player_season PRIMARY KEY (player_key, club_key, competition_key, season_key)
);

CREATE TABLE dbo.fact_club_season_summary
(
    club_key         INT      NOT NULL REFERENCES dbo.dim_club (club_key),
    competition_key  INT      NOT NULL REFERENCES dbo.dim_competition (competition_key),
    season_key       INT      NOT NULL REFERENCES dbo.dim_season (season_key),
    matches_played   INT      NOT NULL,
    wins             INT      NOT NULL,
    draws            INT      NOT NULL,
    losses           INT      NOT NULL,
    goals_for        INT      NOT NULL,
    goals_against    INT      NOT NULL,
    clean_sheets     INT      NOT NULL,
    points           INT      NOT NULL,   -- 3 x wins + draws
    batch_id         NVARCHAR(30) NULL,
    CONSTRAINT pk_fact_club_season PRIMARY KEY (club_key, competition_key, season_key)
);
GO

/* ---------- Điều khiển nạp gia tăng ---------- */
-- Cửa sổ nạp: mỗi lần chạy ETL chỉ đưa vào kho các sự kiện có ngày nằm trong [window_from, window_to].
-- Demo: đợt 1 (<= 2018) -> đợt 2 (2019-2021) -> đợt 3 (>= 2022); chạy lại một đợt không sinh thêm dòng.
CREATE TABLE dbo.etl_load_window
(
    id           TINYINT NOT NULL PRIMARY KEY CHECK (id = 1),   -- chỉ một dòng cấu hình
    window_from  DATE    NOT NULL,
    window_to    DATE    NOT NULL
);
INSERT dbo.etl_load_window (id, window_from, window_to) VALUES (1, '1900-01-01', '9999-12-31');

-- Nhật ký: mỗi lần chạy một dòng
CREATE TABLE dbo.etl_batch
(
    run_id         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    batch_id       NVARCHAR(30)  NULL,
    window_from    DATE          NULL,
    window_to      DATE          NULL,
    started_at     DATETIME      NOT NULL DEFAULT (GETDATE()),
    finished_at    DATETIME      NULL,
    status         NVARCHAR(20)  NOT NULL DEFAULT (N'RUNNING'),
    fact_rows_before INT         NULL,
    fact_rows_after  INT         NULL
);
GO

/* =====================================================================
   DỮ LIỆU SINH SẴN + DÒNG UNKNOWN (key = -1)
   ===================================================================== */

/* ---------- Dim_Date: Unknown + 1990-01-01 .. 2030-12-31 ---------- */
SET DATEFIRST 1;   -- Monday = 1
INSERT dbo.dim_date (date_key, full_date, day_of_week, day_name, is_weekend, [month], month_name, [quarter], [year], is_future_date)
VALUES (-1, NULL, 0, N'Unknown', 0, 0, N'Unknown', 0, 0, 0);

;WITH n AS (
    SELECT TOP (DATEDIFF(DAY, '1990-01-01', '2030-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
), d AS (
    SELECT DATEADD(DAY, i, CAST('1990-01-01' AS DATE)) AS dt FROM n
)
INSERT dbo.dim_date (date_key, full_date, day_of_week, day_name, is_weekend, [month], month_name, [quarter], [year], is_future_date)
SELECT CONVERT(INT, CONVERT(CHAR(8), dt, 112)),
       dt,
       DATEPART(WEEKDAY, dt),
       LEFT(DATENAME(WEEKDAY, dt), 10),
       CASE WHEN DATEPART(WEEKDAY, dt) IN (6, 7) THEN 1 ELSE 0 END,
       MONTH(dt),
       LEFT(DATENAME(MONTH, dt), 10),
       DATEPART(QUARTER, dt),
       YEAR(dt),
       CASE WHEN dt > CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END
FROM d;
GO

/* ---------- Dim_Season: Unknown + mùa 1990/91 .. 2030/31 ---------- */
SET IDENTITY_INSERT dbo.dim_season ON;
INSERT dbo.dim_season (season_key, season_start_year, season_label, season_short)
VALUES (-1, -1, N'Unknown', N'Unknown');
SET IDENTITY_INSERT dbo.dim_season OFF;

;WITH y AS (SELECT 1990 AS yr UNION ALL SELECT yr + 1 FROM y WHERE yr < 2030)
INSERT dbo.dim_season (season_start_year, season_label, season_short)
SELECT yr,
       CAST(yr AS NVARCHAR(4)) + N'/' + RIGHT(N'0' + CAST((yr + 1) % 100 AS NVARCHAR(2)), 2),
       RIGHT(N'0' + CAST(yr % 100 AS NVARCHAR(2)), 2) + N'/' + RIGHT(N'0' + CAST((yr + 1) % 100 AS NVARCHAR(2)), 2)
FROM y
OPTION (MAXRECURSION 100);
GO

/* ---------- Dim_Transfer_Type: tổ hợp fee_status x fee_band (khớp nhãn của P4) ---------- */
INSERT dbo.dim_transfer_type (transfer_type_key, fee_status, fee_band) VALUES
    (-1, N'Không xác định',          N'Không xác định'),
    ( 1, N'Không công bố',           N'Không áp dụng'),
    ( 2, N'Miễn phí hoặc cho mượn',  N'Không áp dụng'),
    ( 3, N'Có phí',                  N'< 1 triệu'),
    ( 4, N'Có phí',                  N'1-10 triệu'),
    ( 5, N'Có phí',                  N'10-50 triệu'),
    ( 6, N'Có phí',                  N'> 50 triệu');
GO

/* ---------- Dòng Unknown cho các dimension nạp từ nguồn ---------- */
SET IDENTITY_INSERT dbo.dim_competition ON;
INSERT dbo.dim_competition (competition_key, competition_id, competition_name, competition_type, competition_sub_type, country_name, confederation)
VALUES (-1, N'-1', N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định');
SET IDENTITY_INSERT dbo.dim_competition OFF;

SET IDENTITY_INSERT dbo.dim_club ON;
INSERT dbo.dim_club (club_key, club_id, club_name, club_type, country_name, confederation, current_league_id, current_league_name,
                     previous_league_name, stadium_name, stadium_capacity_band, effective_date, expiry_date, is_current)
VALUES (-1, -1, N'Không xác định', N'Other', N'Không xác định', N'Không xác định', NULL, N'Không xác định',
        NULL, N'Không xác định', N'Không xác định', '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dbo.dim_club OFF;

SET IDENTITY_INSERT dbo.dim_player ON;
INSERT dbo.dim_player (player_key, player_id, full_name, date_of_birth, country_of_birth, citizenship, position, sub_position, foot,
                       height_band, agent_name, contract_expiry_year, international_caps_band, effective_date, expiry_date, is_current)
VALUES (-1, -1, N'Không xác định', NULL, N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định',
        N'Không xác định', N'Không xác định', NULL, N'Không xác định', '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dbo.dim_player OFF;

SET IDENTITY_INSERT dbo.dim_match ON;
INSERT dbo.dim_match (match_key, game_id, [round], round_type, stadium, referee, home_formation, away_formation, attendance_band)
VALUES (-1, -1, N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định', N'Không xác định');
SET IDENTITY_INSERT dbo.dim_match OFF;

SET IDENTITY_INSERT dbo.dim_manager ON;
INSERT dbo.dim_manager (manager_key, manager_name) VALUES (-1, N'Không xác định');
SET IDENTITY_INSERT dbo.dim_manager OFF;
GO

/* =====================================================================
   SCD Type 2: đóng phiên bản hiện tại và thêm phiên bản mới (gọi từ OLE DB Command)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_DimClub_NewVersion
    @club_key INT, @club_name NVARCHAR(200), @club_type NVARCHAR(20), @country_name NVARCHAR(100),
    @confederation NVARCHAR(20), @current_league_id NVARCHAR(20), @current_league_name NVARCHAR(200),
    @stadium_name NVARCHAR(200), @stadium_capacity_band NVARCHAR(30), @batch_id NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    INSERT dbo.dim_club (club_id, club_name, club_type, country_name, confederation, current_league_id, current_league_name,
                         previous_league_name, stadium_name, stadium_capacity_band, effective_date, expiry_date, is_current, batch_id)
    SELECT d.club_id, @club_name, @club_type, @country_name, @confederation, @current_league_id, @current_league_name,
           CASE WHEN ISNULL(@current_league_id, N'') <> ISNULL(d.current_league_id, N'') THEN d.current_league_name ELSE d.previous_league_name END,
           @stadium_name, @stadium_capacity_band, CAST(GETDATE() AS DATE), '9999-12-31', 1, @batch_id
    FROM dbo.dim_club d WHERE d.club_key = @club_key;
    UPDATE dbo.dim_club SET expiry_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), is_current = 0 WHERE club_key = @club_key;
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DimPlayer_NewVersion
    @player_key INT, @full_name NVARCHAR(200), @date_of_birth DATE, @country_of_birth NVARCHAR(100), @citizenship NVARCHAR(100),
    @position NVARCHAR(50), @sub_position NVARCHAR(50), @foot NVARCHAR(20), @height_band NVARCHAR(30), @agent_name NVARCHAR(200),
    @contract_expiry_year SMALLINT, @international_caps_band NVARCHAR(30), @batch_id NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    INSERT dbo.dim_player (player_id, full_name, date_of_birth, country_of_birth, citizenship, position, sub_position, foot,
                           height_band, agent_name, contract_expiry_year, international_caps_band, effective_date, expiry_date, is_current, batch_id)
    SELECT d.player_id, @full_name, @date_of_birth, @country_of_birth, @citizenship, @position, @sub_position, @foot,
           @height_band, @agent_name, @contract_expiry_year, @international_caps_band, CAST(GETDATE() AS DATE), '9999-12-31', 1, @batch_id
    FROM dbo.dim_player d WHERE d.player_key = @player_key;
    UPDATE dbo.dim_player SET expiry_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), is_current = 0 WHERE player_key = @player_key;
    COMMIT;
END;
GO
