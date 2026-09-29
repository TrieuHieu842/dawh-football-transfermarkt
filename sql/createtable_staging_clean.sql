DROP TABLE IF EXISTS dbo.stg_clean_players;
GO

CREATE TABLE dbo.stg_clean_players
(
    player_id                INT NULL,
    full_name                NVARCHAR(200) NULL,
    first_name               NVARCHAR(100) NULL,
    last_name                NVARCHAR(100) NULL,

    date_of_birth            DATE NULL,

    country_of_birth         NVARCHAR(100) NULL,
    country_of_citizenship   NVARCHAR(100) NULL,

    position                 NVARCHAR(100) NULL,
    sub_position             NVARCHAR(100) NULL,
    foot                     NVARCHAR(50) NULL,

    height_in_cm             DECIMAL(6,2) NULL,
    height_band              NVARCHAR(50) NULL,

    current_club_id          INT NULL,
    current_club_name        NVARCHAR(200) NULL,

    current_national_team_id INT NULL,

    contract_expiration_date DATE NULL,

    market_value_in_eur      DECIMAL(19,2) NULL,
    highest_market_value_in_eur DECIMAL(19,2) NULL,

    batch_id                 NVARCHAR(100) NULL,
    loaded_at                DATETIME NULL,
    source_file              NVARCHAR(1000) NULL
);
GO