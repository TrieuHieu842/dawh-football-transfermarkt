/* =====================================================================
   p4_ssis_source_queries.sql  (Nguoi 4)
   Cac cau SQL dang dung trong P4_Clean_Valuations_Transfers.dtsx.
   Moi khoi ghi ro thuoc component nao.
   ===================================================================== */
USE football_dwh_staging;
GO

/* ---------------------------------------------------------------------
   [1] Execute SQL Task: EST_Truncate_Valuations
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.player_valuations;
DELETE FROM dbo.etl_reject WHERE source_table = N'stg_raw_player_valuations';
GO

/* ---------------------------------------------------------------------
   [2] DFT_Clean_Valuations -> OLE_SRC_Valuations (SQL command)
   Khu trung (player_id, valuation_date) truoc khi tinh LAG; lan dinh gia dau -> value_change_eur NULL.
   --------------------------------------------------------------------- */
WITH src AS
(
    SELECT
        TRY_CAST(
            NULLIF(LTRIM(RTRIM(CAST(player_id AS NVARCHAR(50)))), '')
            AS INT
        ) AS player_id,

        TRY_CAST(
            NULLIF(
                LEFT(LTRIM(RTRIM(CAST([date] AS NVARCHAR(50)))), 10),
                ''
            )
            AS DATE
        ) AS valuation_date,

        TRY_CAST(
            NULLIF(
                LTRIM(RTRIM(CAST(market_value_in_eur AS NVARCHAR(50)))),
                ''
            )
            AS BIGINT
        ) AS market_value_eur,

        TRY_CAST(
            NULLIF(
                LTRIM(RTRIM(CAST(current_club_id AS NVARCHAR(50)))),
                ''
            )
            AS INT
        ) AS current_club_id,

        CAST(
            NULLIF(
                LTRIM(RTRIM(
                    REPLACE(
                        CAST(player_club_domestic_competition_id AS NVARCHAR(20)),
                        NCHAR(160),
                        N' '
                    )
                )),
                ''
            )
            AS NVARCHAR(20)
        ) AS competition_id,

        CAST(batch_id AS NVARCHAR(30)) AS batch_id,
        loaded_at

    FROM dbo.stg_raw_player_valuations
),
dedup AS
(
    SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, valuation_date ORDER BY loaded_at DESC) AS rn
    FROM src
),
calc AS
(
    SELECT
        player_id,
        valuation_date,
        market_value_eur,
        current_club_id,
        competition_id,

        market_value_eur
        - LAG(market_value_eur) OVER
        (
            PARTITION BY player_id
            ORDER BY valuation_date
        ) AS value_change_eur,

        batch_id,
        loaded_at
    FROM dedup
    WHERE rn = 1 OR player_id IS NULL OR valuation_date IS NULL
)
SELECT
    player_id,
    valuation_date,
    market_value_eur,
    current_club_id,
    competition_id,
    value_change_eur,
    batch_id,
    loaded_at
FROM calc;
GO

/* ---------------------------------------------------------------------
   [3] DFT_Clean_Valuations -> LKP_Player_DOB_Valuation (Lookup)
   --------------------------------------------------------------------- */
SELECT
    player_id,
    CAST(date_of_birth AS DATE) AS date_of_birth
FROM stg_clean.players;
GO

/* ---------------------------------------------------------------------
   [4] Execute SQL Task: EST_Truncate_Transfers
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.transfers;
DELETE FROM dbo.etl_reject WHERE source_table = N'stg_raw_transfers';
GO

/* ---------------------------------------------------------------------
   [5] DFT_Clean_Transfers -> OLE_SRC_Transfers (SQL command)
   Tien dang '700000.000' nen ep qua DECIMAL roi moi BIGINT (ep thang BIGINT ra NULL).
   Khu trung theo (player_id, transfer_date, from_club_id, to_club_id).
   --------------------------------------------------------------------- */
/* Khu trung: giu 1 dong moi khoa (player_id, transfer_date, from_club_id, to_club_id), uu tien dong nap sau cung */
SELECT [player_id], [transfer_date], [transfer_season], [from_club_id], [to_club_id], [transfer_fee_eur], [market_value_eur], [batch_id], [loaded_at]
FROM (
    SELECT q.*, ROW_NUMBER() OVER (PARTITION BY q.player_id, q.transfer_date, q.from_club_id, q.to_club_id ORDER BY q.loaded_at DESC) AS rn
    FROM (
SELECT
    TRY_CAST(
        NULLIF(LTRIM(RTRIM(CAST(player_id AS NVARCHAR(50)))), '')
        AS INT
    ) AS player_id,

    TRY_CAST(
        NULLIF(
            LEFT(LTRIM(RTRIM(CAST(transfer_date AS NVARCHAR(50)))), 10),
            ''
        )
        AS DATE
    ) AS transfer_date,

    CAST(
        NULLIF(
            LTRIM(RTRIM(
                REPLACE(
                    CAST(transfer_season AS NVARCHAR(10)),
                    NCHAR(160),
                    N' '
                )
            )),
            ''
        )
        AS NVARCHAR(10)
    ) AS transfer_season,

    TRY_CAST(
        NULLIF(LTRIM(RTRIM(CAST(from_club_id AS NVARCHAR(50)))), '')
        AS INT
    ) AS from_club_id,

    TRY_CAST(
        NULLIF(LTRIM(RTRIM(CAST(to_club_id AS NVARCHAR(50)))), '')
        AS INT
    ) AS to_club_id,

    TRY_CAST(
        TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(transfer_fee AS NVARCHAR(50)))), '') AS DECIMAL(19,3))
        AS BIGINT
    ) AS transfer_fee_eur,

    TRY_CAST(
        TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(market_value_in_eur AS NVARCHAR(50)))), '') AS DECIMAL(19,3))
        AS BIGINT
    ) AS market_value_eur,

    CAST(batch_id AS NVARCHAR(30)) AS batch_id,
    loaded_at

FROM dbo.stg_raw_transfers
    ) q
) d
WHERE d.rn = 1 OR d.player_id IS NULL OR d.transfer_date IS NULL OR d.from_club_id IS NULL OR d.to_club_id IS NULL;
GO

/* ---------------------------------------------------------------------
   [6] DFT_Clean_Transfers -> LKP_Player_DOB_Transfer (Lookup)
   --------------------------------------------------------------------- */
SELECT
    player_id,
    CAST(date_of_birth AS DATE) AS date_of_birth
FROM stg_clean.players;
GO
