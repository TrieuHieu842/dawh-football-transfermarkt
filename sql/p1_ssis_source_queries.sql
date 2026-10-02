/* =====================================================================
   p1_ssis_source_queries.sql  (Nguoi 1)
   Cac cau SQL dung trong SSIS package P1_Clean_Players_Clubs.dtsx.
   Moi khoi ghi ro thuoc component nao.
   ===================================================================== */
USE football_dwh_staging;
GO

/* ---------------------------------------------------------------------
   [1] Execute SQL Task: SQL_Truncate_Players
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.players;
DELETE FROM dbo.etl_reject WHERE source_table = N'stg_raw_players';
GO

/* ---------------------------------------------------------------------
   [2] DFT_Clean_Players -> SRC_raw_players (SQL command)
   Giu dang chuoi; ep kieu lam o Data Conversion (loi -> etl_reject).
   Chuoi rong -> NULL truoc khi ep kieu (TRY_CAST('' AS INT) = 0, khong phai NULL).
   Ngay '1989-02-06 00:00:00' -> lay 10 ky tu dau.
   Khu trung theo player_id, giu dong nap sau cung.
   --------------------------------------------------------------------- */
SELECT player_id, name, date_of_birth, country_of_birth, country_of_citizenship,
       position, sub_position, foot, height_in_cm, agent_name,
       contract_expiration_date, international_caps, batch_id, loaded_at
FROM (
    SELECT CAST(NULLIF(LTRIM(RTRIM(CAST(player_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20))             AS player_id,
           CAST(name                   AS NVARCHAR(200))                                              AS name,
           CAST(NULLIF(LEFT(LTRIM(CAST(date_of_birth AS NVARCHAR(30))), 10), N'') AS NVARCHAR(10))     AS date_of_birth,
           CAST(country_of_birth       AS NVARCHAR(100))                                              AS country_of_birth,
           CAST(country_of_citizenship AS NVARCHAR(100))                                              AS country_of_citizenship,
           CAST(position               AS NVARCHAR(50))                                               AS position,
           CAST(sub_position           AS NVARCHAR(50))                                               AS sub_position,
           CAST(foot                   AS NVARCHAR(20))                                               AS foot,
           CAST(NULLIF(LTRIM(RTRIM(CAST(height_in_cm AS NVARCHAR(10)))), N'') AS NVARCHAR(10))         AS height_in_cm,
           CAST(agent_name             AS NVARCHAR(200))                                              AS agent_name,
           CAST(NULLIF(LEFT(LTRIM(CAST(contract_expiration_date AS NVARCHAR(30))), 10), N'') AS NVARCHAR(10)) AS contract_expiration_date,
           CAST(NULLIF(LTRIM(RTRIM(CAST(international_caps AS NVARCHAR(10)))), N'') AS NVARCHAR(10))   AS international_caps,
           CAST(batch_id AS NVARCHAR(30))                                                             AS batch_id,
           loaded_at,
           ROW_NUMBER() OVER (PARTITION BY CAST(player_id AS NVARCHAR(20)) ORDER BY loaded_at DESC)   AS rn
    FROM dbo.stg_raw_players
) x
WHERE rn = 1 OR player_id IS NULL;
GO

/* ---------------------------------------------------------------------
   [3] Execute SQL Task: SQL_Truncate_Clubs
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.clubs;
DELETE FROM dbo.etl_reject WHERE source_table IN (N'stg_raw_clubs', N'stg_raw_national_teams');
GO

/* ---------------------------------------------------------------------
   [4] DFT_Clean_Clubs -> SRC_raw_clubs (SQL command)
   Quoc gia, lien doan lay tu giai VDQG cua CLB (competitions), chuan hoa tieng Duc -> UEFA, AFC...
   Khu trung theo club_id. Cot giong het khoi [5] de Union All.
   --------------------------------------------------------------------- */
SELECT club_id, club_name, domestic_competition_id, country_name, confederation,
       stadium_name, stadium_seats, batch_id, loaded_at
FROM (
    SELECT CAST(NULLIF(LTRIM(RTRIM(CAST(c.club_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20))                 AS club_id,
           CAST(c.name AS NVARCHAR(200))                                                                    AS club_name,
           CAST(NULLIF(LTRIM(RTRIM(CAST(c.domestic_competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS domestic_competition_id,
           CAST(NULLIF(LTRIM(RTRIM(CAST(k.country_name AS NVARCHAR(100)))), N'') AS NVARCHAR(100))          AS country_name,
           CAST(CASE UPPER(LTRIM(RTRIM(CAST(k.confederation AS NVARCHAR(20)))))
                    WHEN N'EUROPA'  THEN N'UEFA'
                    WHEN N'ASIEN'   THEN N'AFC'
                    WHEN N'AFRIKA'  THEN N'CAF'
                    WHEN N'AMERIKA' THEN N'Americas'
                    WHEN N'FIFA'    THEN N'FIFA'
                    ELSE N'Không xác định'
                END AS NVARCHAR(20))                                                                        AS confederation,
           CAST(c.stadium_name AS NVARCHAR(200))                                                            AS stadium_name,
           CAST(NULLIF(LTRIM(RTRIM(CAST(c.stadium_seats AS NVARCHAR(20)))), N'') AS NVARCHAR(20))           AS stadium_seats,
           CAST(c.batch_id AS NVARCHAR(30))                                                                 AS batch_id,
           c.loaded_at,
           ROW_NUMBER() OVER (PARTITION BY CAST(c.club_id AS NVARCHAR(20)) ORDER BY c.loaded_at DESC)       AS rn
    FROM dbo.stg_raw_clubs c
    LEFT JOIN (SELECT DISTINCT CAST(competition_id AS NVARCHAR(20)) AS competition_id,
                      CAST(country_name AS NVARCHAR(100)) AS country_name,
                      CAST(confederation AS NVARCHAR(20)) AS confederation
               FROM dbo.stg_raw_competitions) k
      ON k.competition_id = CAST(c.domestic_competition_id AS NVARCHAR(20))
) x
WHERE rn = 1 OR club_id IS NULL;
GO

/* ---------------------------------------------------------------------
   [5] DFT_Clean_Clubs -> SRC_raw_national_teams (SQL command)
   Doi tuyen: lay country_name, confederation cua chinh doi tuyen.
   Lien doan nguon da la ten chuan: CONCACAF, CONMEBOL -> Americas; giu nguyen AFC, CAF, UEFA, OFC.
   Khong co giai VDQG, san nha, suc chua -> NULL.
   --------------------------------------------------------------------- */
SELECT club_id, club_name, domestic_competition_id, country_name, confederation,
       stadium_name, stadium_seats, batch_id, loaded_at
FROM (
    SELECT CAST(NULLIF(LTRIM(RTRIM(CAST(national_team_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20))  AS club_id,
           CAST(name AS NVARCHAR(200))                                                              AS club_name,
           CAST(NULL AS NVARCHAR(20))                                                               AS domestic_competition_id,
           CAST(NULLIF(LTRIM(RTRIM(CAST(country_name AS NVARCHAR(100)))), N'') AS NVARCHAR(100))    AS country_name,
           CAST(CASE UPPER(LTRIM(RTRIM(CAST(confederation AS NVARCHAR(20)))))
                    WHEN N'UEFA'     THEN N'UEFA'
                    WHEN N'AFC'      THEN N'AFC'
                    WHEN N'CAF'      THEN N'CAF'
                    WHEN N'CONCACAF' THEN N'Americas'
                    WHEN N'CONMEBOL' THEN N'Americas'
                    WHEN N'OFC'      THEN N'OFC'
                    WHEN N'FIFA'     THEN N'FIFA'
                    ELSE N'Không xác định'
                END AS NVARCHAR(20))                                                                AS confederation,
           CAST(NULL AS NVARCHAR(200))                                                              AS stadium_name,
           CAST(NULL AS NVARCHAR(20))                                                               AS stadium_seats,
           CAST(batch_id AS NVARCHAR(30))                                                           AS batch_id,
           loaded_at,
           ROW_NUMBER() OVER (PARTITION BY CAST(national_team_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_national_teams
) x
WHERE rn = 1 OR club_id IS NULL;
GO
