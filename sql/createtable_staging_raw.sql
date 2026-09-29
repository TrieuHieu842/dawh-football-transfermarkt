

CREATE TABLE dbo.stg_raw_players
(
    player_id                           NVARCHAR(MAX) NULL,
    first_name                          NVARCHAR(MAX) NULL,
    last_name                           NVARCHAR(MAX) NULL,
    name                                NVARCHAR(MAX) NULL,
    last_season                         NVARCHAR(MAX) NULL,
    current_club_id                     NVARCHAR(MAX) NULL,
    player_code                         NVARCHAR(MAX) NULL,
    country_of_birth                    NVARCHAR(MAX) NULL,
    city_of_birth                       NVARCHAR(MAX) NULL,
    country_of_citizenship              NVARCHAR(MAX) NULL,
    date_of_birth                       NVARCHAR(MAX) NULL,
    sub_position                        NVARCHAR(MAX) NULL,
    position                            NVARCHAR(MAX) NULL,
    foot                                NVARCHAR(MAX) NULL,
    height_in_cm                        NVARCHAR(MAX) NULL,
    contract_expiration_date            NVARCHAR(MAX) NULL,
    agent_name                          NVARCHAR(MAX) NULL,
    image_url                           NVARCHAR(MAX) NULL,
    international_caps                  NVARCHAR(MAX) NULL,
    international_goals                 NVARCHAR(MAX) NULL,
    current_national_team_id             NVARCHAR(MAX) NULL,
    url                                 NVARCHAR(MAX) NULL,
    current_club_domestic_competition_id NVARCHAR(MAX) NULL,
    current_club_name                   NVARCHAR(MAX) NULL,
    market_value_in_eur                 NVARCHAR(MAX) NULL,
    highest_market_value_in_eur         NVARCHAR(MAX) NULL,

    batch_id                            NVARCHAR(MAX) NULL,
    loaded_at                           DATETIME NULL,
    source_file                         NVARCHAR(MAX) NULL
);
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

DROP TABLE IF EXISTS [dbo].[stg_raw_games]
GO

CREATE TABLE [dbo].[stg_raw_games](
    [game_id] [nvarchar](max) NULL,
    [competition_id] [nvarchar](max) NULL,
    [season] [nvarchar](max) NULL,
    [round] [nvarchar](max) NULL,
    [date] [nvarchar](max) NULL,
    [home_club_id] [nvarchar](max) NULL,
    [away_club_id] [nvarchar](max) NULL,
    [home_club_goals] [nvarchar](max) NULL,
    [away_club_goals] [nvarchar](max) NULL,
    [home_club_position] [nvarchar](max) NULL,
    [away_club_position] [nvarchar](max) NULL,
    [home_club_manager_name] [nvarchar](max) NULL,
    [away_club_manager_name] [nvarchar](max) NULL,
    [stadium] [nvarchar](max) NULL,
    [attendance] [nvarchar](max) NULL,
    [referee] [nvarchar](max) NULL,
    [url] [nvarchar](max) NULL,
    [home_club_formation] [nvarchar](max) NULL,
    [away_club_formation] [nvarchar](max) NULL,
    [home_club_name] [nvarchar](max) NULL,
    [away_club_name] [nvarchar](max) NULL,
    [aggregate] [nvarchar](max) NULL,
    [competition_type] [nvarchar](max) NULL,

    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


CREATE TABLE [dbo].[stg_raw_clubs](
    [club_id] [nvarchar](max) NULL,
    [club_code] [nvarchar](max) NULL,
    [name] [nvarchar](max) NULL,
    [domestic_competition_id] [nvarchar](max) NULL,
    [total_market_value] [nvarchar](max) NULL,
    [squad_size] [nvarchar](max) NULL,
    [average_age] [nvarchar](max) NULL,
    [foreigners_number] [nvarchar](max) NULL,
    [foreigners_percentage] [nvarchar](max) NULL,
    [national_team_players] [nvarchar](max) NULL,
    [stadium_name] [nvarchar](max) NULL,
    [stadium_seats] [nvarchar](max) NULL,
    [net_transfer_record] [nvarchar](max) NULL,
    [coach_name] [nvarchar](max) NULL,
    [last_season] [nvarchar](max) NULL,
    [filename] [nvarchar](max) NULL,
    [url] [nvarchar](max) NULL,

    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[stg_raw_appearances](
    [appearance_id] [nvarchar](max) NULL,
    [game_id] [nvarchar](max) NULL,
    [player_id] [nvarchar](max) NULL,
    [player_club_id] [nvarchar](max) NULL,
    [player_current_club_id] [nvarchar](max) NULL,
    [date] [nvarchar](max) NULL,
    [player_name] [nvarchar](max) NULL,
    [competition_id] [nvarchar](max) NULL,
    [yellow_cards] [nvarchar](max) NULL,
    [red_cards] [nvarchar](max) NULL,
    [goals] [nvarchar](max) NULL,
    [assists] [nvarchar](max) NULL,
    [minutes_played] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[stg_raw_competitions](
    [competition_id] [nvarchar](max) NULL,
    [competition_code] [nvarchar](max) NULL,
    [name] [nvarchar](max) NULL,
    [sub_type] [nvarchar](max) NULL,
    [type] [nvarchar](max) NULL,
    [country_id] [nvarchar](max) NULL,
    [country_name] [nvarchar](max) NULL,
    [domestic_league_code] [nvarchar](max) NULL,
    [confederation] [nvarchar](max) NULL,
    [total_clubs] [nvarchar](max) NULL,
    [url] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[stg_raw_countries](
    [country_id] [nvarchar](max) NULL,
    [country_name] [nvarchar](max) NULL,
    [country_code] [nvarchar](max) NULL,
    [confederation] [nvarchar](max) NULL,
    [total_clubs] [nvarchar](max) NULL,
    [total_players] [nvarchar](max) NULL,
    [average_age] [nvarchar](max) NULL,
    [url] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[stg_raw_club_games](
    [game_id] [nvarchar](max) NULL,
    [club_id] [nvarchar](max) NULL,
    [own_goals] [nvarchar](max) NULL,
    [own_position] [nvarchar](max) NULL,
    [own_manager_name] [nvarchar](max) NULL,
    [opponent_id] [nvarchar](max) NULL,
    [opponent_goals] [nvarchar](max) NULL,
    [opponent_position] [nvarchar](max) NULL,
    [opponent_manager_name] [nvarchar](max) NULL,
    [hosting] [nvarchar](max) NULL,
    [is_win] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[stg_raw_transfers](
    [player_id] [nvarchar](max) NULL,
    [transfer_date] [nvarchar](max) NULL,
    [transfer_season] [nvarchar](max) NULL,
    [from_club_id] [nvarchar](max) NULL,
    [to_club_id] [nvarchar](max) NULL,
    [from_club_name] [nvarchar](max) NULL,
    [to_club_name] [nvarchar](max) NULL,
    [transfer_fee] [nvarchar](max) NULL,
    [market_value_in_eur] [nvarchar](max) NULL,
    [player_name] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

DROP TABLE IF EXISTS dbo.stg_raw_national_teams
GO

CREATE TABLE [dbo].[stg_raw_national_teams](
    [national_team_id] [nvarchar](max) NULL,
    [name] [nvarchar](max) NULL,
    [team_code] [nvarchar](max) NULL,
    [country_id] [nvarchar](max) NULL,
    [country_name] [nvarchar](max) NULL,
    [country_code] [nvarchar](max) NULL,
    [confederation] [nvarchar](max) NULL,
    [team_image_url] [nvarchar](max) NULL,
    [squad_size] [nvarchar](max) NULL,
    [average_age] [nvarchar](max) NULL,
    [foreigners_number] [nvarchar](max) NULL,
    [foreigners_percentage] [nvarchar](max) NULL,
    [total_market_value] [nvarchar](max) NULL,
    [coach_name] [nvarchar](max) NULL,
    [fifa_ranking] [nvarchar](max) NULL,
    [last_season] [nvarchar](max) NULL,
    [url] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[stg_raw_player_valuations](
    [player_id] [nvarchar](max) NULL,
    [date] [nvarchar](max) NULL,
    [market_value_in_eur] [nvarchar](max) NULL,
    [current_club_name] [nvarchar](max) NULL,
    [current_club_id] [nvarchar](max) NULL,
    [player_club_domestic_competition_id] [nvarchar](max) NULL,
    [batch_id] [nvarchar](max) NULL,
    [loaded_at] [datetime] NULL,
    [source_file] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO