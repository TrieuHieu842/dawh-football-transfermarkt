-- Tao cac bang tang Staging Clean (schema stg_clean) + bang etl_reject cho Container 02.
-- Cot va quy tac lay theo tai lieu thiet ke Kimball (muc 2.3, 7.2, 8.3).
-- Chay 1 lan truoc khi lam Container 02. Chay lai se xoa va tao lai cac bang nay.

USE football_dwh_staging;
GO
IF SCHEMA_ID(N'stg_clean') IS NULL EXEC('CREATE SCHEMA stg_clean');
GO

-- ============================================================
-- Nguoi 1: players, clubs (+ national_teams)
-- ============================================================
DROP TABLE IF EXISTS stg_clean.players;
CREATE TABLE stg_clean.players (
    player_id               INT            NOT NULL PRIMARY KEY,
    player_name             NVARCHAR(200)  NULL,
    date_of_birth           DATE           NULL,
    country_of_birth        NVARCHAR(100)  NULL,
    citizenship             NVARCHAR(100)  NULL,
    position                NVARCHAR(50)   NULL,
    sub_position            NVARCHAR(50)   NULL,
    foot                    NVARCHAR(20)   NULL,
    height_in_cm            SMALLINT       NULL,          -- ngoai 150-220 -> NULL
    height_band             NVARCHAR(30)   NOT NULL,      -- < 170 cm | 170-179 | 180-189 | >= 190 | Không xác định
    agent_name              NVARCHAR(200)  NULL,
    contract_expiry_year    SMALLINT       NULL,
    international_caps_band NVARCHAR(30)   NOT NULL,      -- Chưa khoác áo | 1-10 | 11-50 | > 50 | Không xác định
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL
);

DROP TABLE IF EXISTS stg_clean.clubs;
CREATE TABLE stg_clean.clubs (
    club_id                 INT            NOT NULL PRIMARY KEY,
    club_name               NVARCHAR(200)  NULL,
    club_type               NVARCHAR(20)   NOT NULL,      -- Club | National Team
    domestic_competition_id NVARCHAR(20)   NULL,
    country_name            NVARCHAR(100)  NULL,          -- CLB: lay theo giai VDQG (competitions); doi tuyen: national_teams
    confederation           NVARCHAR(20)   NULL,          -- chuan hoa: UEFA | AFC | CAF | Americas | OFC | FIFA | Không xác định
    stadium_name            NVARCHAR(200)  NULL,
    stadium_capacity_band   NVARCHAR(30)   NOT NULL,      -- < 20.000 | 20.000-39.999 | 40.000-59.999 | >= 60.000 | Không xác định
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL
);

-- ============================================================
-- Nguoi 2: competitions (+ countries), games
-- ============================================================
DROP TABLE IF EXISTS stg_clean.competitions;
CREATE TABLE stg_clean.competitions (
    competition_id          NVARCHAR(20)   NOT NULL PRIMARY KEY,
    competition_name        NVARCHAR(200)  NULL,
    competition_type        NVARCHAR(50)   NULL,
    competition_sub_type    NVARCHAR(50)   NULL,
    country_name            NVARCHAR(100)  NOT NULL,      -- giai quoc te ghi International
    confederation           NVARCHAR(20)   NOT NULL,      -- UEFA | AFC | CAF | Americas | FIFA | Không xác định
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL
);

DROP TABLE IF EXISTS stg_clean.games;
CREATE TABLE stg_clean.games (
    game_id                 INT            NOT NULL PRIMARY KEY,
    competition_id          NVARCHAR(20)   NULL,
    season_start_year       SMALLINT       NULL,          -- 2024
    season_label            NVARCHAR(10)   NULL,          -- 2024/25
    season_short            NVARCHAR(10)   NULL,          -- 24/25 (khop voi transfers.transfer_season)
    game_date               DATE           NULL,
    round                   NVARCHAR(100)  NULL,
    round_type              NVARCHAR(20)   NOT NULL,      -- Matchday | Group stage | Knockout | Final
    stadium                 NVARCHAR(200)  NULL,
    referee                 NVARCHAR(200)  NULL,
    home_formation          NVARCHAR(30)   NULL,
    away_formation          NVARCHAR(30)   NULL,
    attendance_band         NVARCHAR(30)   NOT NULL,      -- < 10.000 | 10.000-29.999 | 30.000-59.999 | >= 60.000 | Không xác định
    home_club_id            INT            NULL,          -- giu de doi chieu DQ (muc 9)
    away_club_id            INT            NULL,
    home_club_goals         SMALLINT       NULL,
    away_club_goals         SMALLINT       NULL,
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL
);

-- ============================================================
-- Nguoi 3: club_games, appearances
-- ============================================================
DROP TABLE IF EXISTS stg_clean.club_games;
CREATE TABLE stg_clean.club_games (
    game_id                 INT            NOT NULL,
    club_id                 INT            NOT NULL,
    opponent_id             INT            NULL,
    own_goals               SMALLINT       NULL,
    opponent_goals          SMALLINT       NULL,
    own_position            SMALLINT       NULL,          -- '' hoac -1 -> NULL
    own_manager_name        NVARCHAR(200)  NULL,
    opponent_manager_name   NVARCHAR(200)  NULL,
    is_home                 BIT            NULL,
    is_win                  BIT            NULL,          -- tinh lai tu ti so, KHONG lay cot is_win nguon
    is_draw                 BIT            NULL,
    is_loss                 BIT            NULL,
    is_clean_sheet          BIT            NULL,
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL,
    CONSTRAINT PK_stg_clean_club_games PRIMARY KEY (game_id, club_id)
);

DROP TABLE IF EXISTS stg_clean.appearances;
CREATE TABLE stg_clean.appearances (
    appearance_id           NVARCHAR(50)   NOT NULL PRIMARY KEY,
    game_id                 INT            NOT NULL,
    player_id               INT            NOT NULL,
    player_club_id          INT            NULL,
    game_date               DATE           NULL,
    competition_id          NVARCHAR(20)   NULL,
    minutes_played          SMALLINT       NULL,
    goals                   SMALLINT       NULL,
    assists                 SMALLINT       NULL,
    yellow_cards            SMALLINT       NULL,
    red_cards               SMALLINT       NULL,
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL
);

-- ============================================================
-- Nguoi 4: player_valuations, transfers
-- ============================================================
DROP TABLE IF EXISTS stg_clean.player_valuations;
CREATE TABLE stg_clean.player_valuations (
    player_id               INT            NOT NULL,
    valuation_date          DATE           NOT NULL,
    market_value_eur        BIGINT         NULL,
    current_club_id         INT            NULL,
    competition_id          NVARCHAR(20)   NULL,          -- player_club_domestic_competition_id
    value_change_eur        BIGINT         NULL,          -- lan dinh gia dau tien = NULL
    age_at_valuation        TINYINT        NULL,
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL,
    CONSTRAINT PK_stg_clean_player_valuations PRIMARY KEY (player_id, valuation_date)
);

DROP TABLE IF EXISTS stg_clean.transfers;
CREATE TABLE stg_clean.transfers (
    player_id               INT            NOT NULL,
    transfer_date           DATE           NULL,
    transfer_season         NVARCHAR(10)   NULL,          -- 24/25
    from_club_id            INT            NULL,
    to_club_id              INT            NULL,
    transfer_fee_eur        BIGINT         NULL,          -- rong = NULL (khong cong bo), 0 = mien phi/cho muon
    market_value_eur        BIGINT         NULL,
    fee_status              NVARCHAR(40)   NOT NULL,      -- Có phí | Miễn phí hoặc cho mượn | Không công bố
    fee_band                NVARCHAR(30)   NOT NULL,      -- < 1 triệu | 1-10 triệu | 10-50 triệu | > 50 triệu | Không áp dụng
    fee_premium_eur         BIGINT         NULL,          -- NULL neu phi hoac gia tri thieu
    age_at_transfer         TINYINT        NULL,
    is_future_transfer      BIT            NOT NULL,      -- transfer_date > ngay nap
    batch_id                NVARCHAR(30)   NULL,
    loaded_at               DATETIME       NULL
);

-- ============================================================
-- Dung chung: bang ghi dong bi loai
-- ============================================================
DROP TABLE IF EXISTS dbo.etl_reject;
CREATE TABLE dbo.etl_reject (
    reject_id               BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id                NVARCHAR(30)   NULL,
    source_table            NVARCHAR(100)  NOT NULL,      -- vd: stg_raw_players
    natural_key             NVARCHAR(200)  NULL,          -- vd: player_id=12345
    reason                  NVARCHAR(200)  NOT NULL,      -- vd: Thiếu khóa | Sai kiểu | Trùng lặp | Ngoài ngưỡng
    rejected_at             DATETIME       NOT NULL DEFAULT GETDATE()
);
GO
