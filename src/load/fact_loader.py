import pandas as pd
import numpy as np
from sqlalchemy import Engine
from src.utils.logger import logger

SCHEMA_DW = "dw"
SCHEMA_STG_CLEAN = "stg_clean"

def lookup_date_key(date_series: pd.Series) -> pd.Series:
    """Chuyển đổi chuỗi ngày YYYY-MM-DD sang date_key dạng số YYYYMMDD (ví dụ: 20260928)."""
    dt_series = pd.to_datetime(date_series, errors="coerce")
    date_keys = dt_series.dt.strftime("%Y%m%d")
    return pd.to_numeric(date_keys, errors="coerce").fillna(-1).astype("int64")

def lookup_surrogate_key_scd1(
    df_fact: pd.DataFrame,
    df_dim: pd.DataFrame,
    natural_key: str,
    sk_name: str
) -> pd.Series:
    """Tra cứu Khóa Thay Thế cho Bảng Chiều SCD Type 1."""
    merged = df_fact.merge(
        df_dim[[natural_key, sk_name]],
        on=natural_key,
        how="left"
    )
    return merged[sk_name].fillna(-1).astype("int64")

def lookup_player_key_scd2(
    df_fact: pd.DataFrame,
    df_dim_player: pd.DataFrame,
    event_date_col: str
) -> pd.Series:
    """
    Tra cứu player_key cho Bảng Chiều SCD Type 2 dựa trên khoảng thời gian có hiệu lực:
    effective_date <= event_date <= expiry_date
    """
    # Lấy các cột cần thiết từ dim_player
    dim_subset = df_dim_player[["player_id", "player_key", "effective_date", "expiry_date"]].copy()
    dim_subset["effective_date"] = pd.to_datetime(dim_subset["effective_date"])
    dim_subset["expiry_date"] = pd.to_datetime(dim_subset["expiry_date"])
    
    fact_temp = df_fact[["player_id", event_date_col]].copy()
    fact_temp["event_date_dt"] = pd.to_datetime(fact_temp[event_date_col])
    
    # Merge theo player_id
    merged = fact_temp.merge(dim_subset, on="player_id", how="left")
    
    # Lọc dòng thỏa mãn khoảng thời gian có hiệu lực
    valid_mask = (
        (merged["event_date_dt"] >= merged["effective_date"]) &
        (merged["event_date_dt"] <= merged["expiry_date"])
    )
    
    valid_matches = merged[valid_mask].copy()
    
    # Trường hợp không khớp phiên bản, lấy bản ghi có is_current = 1 hoặc trả về -1
    result = df_fact.merge(
        valid_matches[["player_id", event_date_col, "player_key"]],
        on=["player_id", event_date_col],
        how="left"
    )
    
    return result["player_key"].fillna(-1).astype("int64")

# ==============================================================================
# LOGIC NẠP TỪNG BẢNG FACT
# ==============================================================================

def load_fact_team_match(engine: Engine):
    """Nạp Bảng Sự Kiện Fact_Team_Match."""
    logger.info("Đang nạp Bảng Sự Kiện: [fact_team_match]...")
    
    df_stg = pd.read_sql_table("stg_clean_club_games", con=engine, schema=SCHEMA_STG_CLEAN if "postgresql" in engine.dialect.name else None)
    df_games_raw = pd.read_sql_table("stg_raw_games", con=engine, schema="stg_raw" if "postgresql" in engine.dialect.name else None)
    df_dim_comp = pd.read_sql_table("dim_competition", con=engine, schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None)

    # --- KHẮC PHỤC LỖI: Ép kiểu game_id của df_games_raw về int64 trước khi merge ---
    df_games_raw["game_id"] = pd.to_numeric(df_games_raw["game_id"], errors="coerce").astype("int64")

    # Ghép lấy ngày trận đấu và mã giải đấu từ games
    df_merged = df_stg.merge(
        df_games_raw[["game_id", "date", "competition_id"]],
        on="game_id",
        how="left"
    )

    df_fact = pd.DataFrame()
    df_fact["game_id"] = df_merged["game_id"]
    df_fact["club_id"] = df_merged["club_id"]
    df_fact["opponent_club_id"] = df_merged["opponent_id"]
    
    # Tra cứu SK
    df_fact["date_key"] = lookup_date_key(df_merged["date"])
    df_fact["competition_key"] = lookup_surrogate_key_scd1(df_merged, df_dim_comp, "competition_id", "competition_key")
    
    # Các chỉ số đo lường (Measures)
    df_fact["own_goals"] = df_merged["own_goals"]
    df_fact["opponent_goals"] = df_merged["opponent_goals"]
    df_fact["is_win"] = df_merged["is_win"]
    df_fact["is_draw"] = df_merged["is_draw"]
    df_fact["is_loss"] = df_merged["is_loss"]
    df_fact["is_clean_sheet"] = df_merged["is_clean_sheet"]
    df_fact["batch_id"] = df_merged["batch_id"]

    df_fact.to_sql(
        name="fact_team_match",
        con=engine,
        schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
        if_exists="replace",
        index=False
    )
    logger.info(f"---> [Thành công] Đã nạp {len(df_fact):,} dòng vào [fact_team_match].")

def load_fact_player_valuation(engine: Engine):
    """Nạp Bảng Sự Kiện Fact_Player_Valuation (Periodic Snapshot Fact)."""
    logger.info("Đang nạp Bảng Sự Kiện: [fact_player_valuation]...")
    
    df_stg = pd.read_sql_table("stg_clean_player_valuations", con=engine, schema=SCHEMA_STG_CLEAN if "postgresql" in engine.dialect.name else None)
    df_dim_player = pd.read_sql_table("dim_player", con=engine, schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None)

    df_fact = pd.DataFrame()
    df_fact["date_key"] = lookup_date_key(df_stg["valuation_date"])
    df_fact["player_key"] = lookup_player_key_scd2(df_stg, df_dim_player, "valuation_date")
    df_fact["market_value_in_eur"] = df_stg["market_value_in_eur"]
    df_fact["value_change_eur"] = df_stg["value_change_eur"]
    df_fact["age_at_valuation"] = df_stg["age_at_valuation"]
    df_fact["batch_id"] = df_stg["batch_id"]

    df_fact.to_sql(
        name="fact_player_valuation",
        con=engine,
        schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
        if_exists="replace",
        index=False
    )
    logger.info(f"---> [Thành công] Đã nạp {len(df_fact):,} dòng vào [fact_player_valuation].")

def load_fact_transfer(engine: Engine):
    """Nạp Bảng Sự Kiện Fact_Transfer (Transaction Fact)."""
    logger.info("Đang nạp Bảng Sự Kiện: [fact_transfer]...")
    
    df_stg = pd.read_sql_table("stg_clean_transfers", con=engine, schema=SCHEMA_STG_CLEAN if "postgresql" in engine.dialect.name else None)
    df_dim_player = pd.read_sql_table("dim_player", con=engine, schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None)

    df_fact = pd.DataFrame()
    df_fact["date_key"] = lookup_date_key(df_stg["transfer_date"])
    df_fact["player_key"] = lookup_player_key_scd2(df_stg, df_dim_player, "transfer_date")
    df_fact["transfer_fee"] = df_stg["transfer_fee"]
    df_fact["market_value_in_eur"] = df_stg["market_value_in_eur"]
    df_fact["fee_premium_eur"] = df_stg["fee_premium_eur"]
    df_fact["fee_band"] = df_stg["fee_band"]
    df_fact["age_at_transfer"] = df_stg["age_at_transfer"]
    df_fact["batch_id"] = df_stg["batch_id"]

    df_fact.to_sql(
        name="fact_transfer",
        con=engine,
        schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
        if_exists="replace",
        index=False
    )
    logger.info(f"---> [Thành công] Đã nạp {len(df_fact):,} dòng vào [fact_transfer].")