import pandas as pd
import numpy as np
from src.transform.clean_helpers import (
    clean_string_column, parse_date_column, safe_to_numeric,
    categorize_height, categorize_fee
)
from src.utils.logger import logger

def transform_stg_clean_players(df_raw: pd.DataFrame) -> pd.DataFrame:
    """Làm sạch bảng cầu thủ (Players)."""
    logger.info("Đang biến đổi dữ liệu: stg_clean_players...")
    df = pd.DataFrame()
    
    df["player_id"] = safe_to_numeric(df_raw["player_id"], "int64")
    df["first_name"] = clean_string_column(df_raw["first_name"])
    df["last_name"] = clean_string_column(df_raw["last_name"])
    df["player_name"] = clean_string_column(df_raw["name"])
    df["date_of_birth"] = parse_date_column(df_raw["date_of_birth"])
    df["country_of_birth"] = clean_string_column(df_raw["country_of_birth"])
    df["country_of_citizenship"] = clean_string_column(df_raw["country_of_citizenship"])
    
    # Ép kiểu chiều cao & Phân nhóm
    height_cm = safe_to_numeric(df_raw["height_in_cm"], "float64")
    df["height_in_cm"] = np.where((height_cm >= 140) & (height_cm <= 220), height_cm, np.nan)
    df["height_band"] = categorize_height(df["height_in_cm"])
    
    df["sub_position"] = clean_string_column(df_raw["sub_position"])
    df["position"] = clean_string_column(df_raw["position"])
    df["foot"] = clean_string_column(df_raw["foot"])
    df["current_club_id"] = safe_to_numeric(df_raw["current_club_id"], "Int64")
    df["agent_name"] = clean_string_column(df_raw["agent_name"])
    
    # Cột kỹ thuật audit
    df["batch_id"] = df_raw["batch_id"]
    
    # Khử trùng lặp theo player_id
    df = df.drop_duplicates(subset=["player_id"], keep="last").dropna(subset=["player_id"])
    return df

def transform_stg_clean_club_games(df_raw: pd.DataFrame) -> pd.DataFrame:
    """Làm sạch bảng kết quả trận đấu của CLB (Club Games) & Suy ra chỉ số Win/Loss/CleanSheet."""
    logger.info("Đang biến đổi dữ liệu: stg_clean_club_games...")
    df = pd.DataFrame()
    
    df["game_id"] = safe_to_numeric(df_raw["game_id"], "int64")
    df["club_id"] = safe_to_numeric(df_raw["club_id"], "int64")
    df["own_goals"] = safe_to_numeric(df_raw["own_goals"], "int64")
    df["opponent_id"] = safe_to_numeric(df_raw["opponent_id"], "int64")
    df["opponent_goals"] = safe_to_numeric(df_raw["opponent_goals"], "int64")
    df["hosting"] = clean_string_column(df_raw["hosting"])
    df["is_win"] = safe_to_numeric(df_raw["is_win"], "int64")
    
    # Suy ra cờ thắng/hòa/thua và sạch lưới
    df["is_draw"] = np.where(df["own_goals"] == df["opponent_goals"], 1, 0)
    df["is_loss"] = np.where(df["own_goals"] < df["opponent_goals"], 1, 0)
    df["is_clean_sheet"] = np.where(df["opponent_goals"] == 0, 1, 0)
    
    df["batch_id"] = df_raw["batch_id"]
    
    # Khử trùng lặp theo game_id + club_id
    df = df.drop_duplicates(subset=["game_id", "club_id"], keep="last")
    return df

def transform_stg_clean_player_valuations(df_raw: pd.DataFrame, df_players_clean: pd.DataFrame) -> pd.DataFrame:
    """Làm sạch bảng định giá cầu thủ & Tính độ tuổi + chênh lệch biến động giá trị."""
    logger.info("Đang biến đổi dữ liệu: stg_clean_player_valuations...")
    df = pd.DataFrame()
    
    df["player_id"] = safe_to_numeric(df_raw["player_id"], "int64")
    df["valuation_date"] = parse_date_column(df_raw["date"])
    df["market_value_in_eur"] = safe_to_numeric(df_raw["market_value_in_eur"], "float64")
    df["current_club_id"] = safe_to_numeric(df_raw["current_club_id"], "Int64")
    
    # Sắp xếp theo cầu thủ và ngày định giá để tính biến động giá trị
    df = df.sort_values(by=["player_id", "valuation_date"]).reset_index(drop=True)
    
    # Tính chênh lệch định giá so với lần trước (LAG / shift)
    df["prev_market_value"] = df.groupby("player_id")["market_value_in_eur"].shift(1)
    df["value_change_eur"] = df["market_value_in_eur"] - df["prev_market_value"].fillna(df["market_value_in_eur"])
    df = df.drop(columns=["prev_market_value"])
    
    # Ghép với ngày sinh từ bảng players để tính tuổi tại thời điểm định giá
    if not df_players_clean.empty:
        df = df.merge(df_players_clean[["player_id", "date_of_birth"]], on="player_id", how="left")
        
        # Tính tuổi (số năm)
        val_date = pd.to_datetime(df["valuation_date"])
        dob_date = pd.to_datetime(df["date_of_birth"])
        df["age_at_valuation"] = (val_date - dob_date).dt.days // 365
        df = df.drop(columns=["date_of_birth"])
    else:
        df["age_at_valuation"] = np.nan
        
    df["batch_id"] = df_raw["batch_id"]
    df = df.drop_duplicates(subset=["player_id", "valuation_date"], keep="last")
    return df

def transform_stg_clean_transfers(df_raw: pd.DataFrame, df_players_clean: pd.DataFrame) -> pd.DataFrame:
    """Làm sạch bảng chuyển nhượng & Tính phí thặng dư (premium_eur) + dải phí."""
    logger.info("Đang biến đổi dữ liệu: stg_clean_transfers...")
    df = pd.DataFrame()
    
    df["player_id"] = safe_to_numeric(df_raw["player_id"], "int64")
    df["transfer_date"] = parse_date_column(df_raw["transfer_date"])
    df["transfer_season"] = clean_string_column(df_raw["transfer_season"])
    df["from_club_id"] = safe_to_numeric(df_raw["from_club_id"], "Int64")
    df["to_club_id"] = safe_to_numeric(df_raw["to_club_id"], "Int64")
    df["transfer_fee"] = safe_to_numeric(df_raw["transfer_fee"], "float64").fillna(0)
    df["market_value_in_eur"] = safe_to_numeric(df_raw["market_value_in_eur"], "float64").fillna(0)
    
    # Phí thặng dư = Phí chuyển nhượng - Giá trị thị trường
    df["fee_premium_eur"] = df["transfer_fee"] - df["market_value_in_eur"]
    df["fee_band"] = categorize_fee(df["transfer_fee"])
    
    # Ghép tính tuổi khi chuyển nhượng
    if not df_players_clean.empty:
        df = df.merge(df_players_clean[["player_id", "date_of_birth"]], on="player_id", how="left")
        t_date = pd.to_datetime(df["transfer_date"])
        dob_date = pd.to_datetime(df["date_of_birth"])
        df["age_at_transfer"] = (t_date - dob_date).dt.days // 365
        df = df.drop(columns=["date_of_birth"])
    else:
        df["age_at_transfer"] = np.nan

    df["batch_id"] = df_raw["batch_id"]
    return df