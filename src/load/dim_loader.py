from datetime import datetime, date
import pandas as pd
import numpy as np
from sqlalchemy import Engine, text
from src.utils.logger import logger

SCHEMA_DW = "dw"

def generate_dim_date(start_year: int = 1990, end_year: int = 2030) -> pd.DataFrame:
    """Sinh bảng chiều Thời gian (Dim_Date) tĩnh."""
    logger.info(f"Đang sinh bảng Dim_Date từ năm {start_year} đến {end_year}...")
    
    date_range = pd.date_range(start=f"{start_year}-01-01", end=f"{end_year}-12-31", freq="D")
    df = pd.DataFrame({"full_date": date_range})
    
    # Khóa ngày dạng số YYYYMMDD (ví dụ: 20260928)
    df["date_key"] = df["full_date"].dt.strftime("%Y%m%d").astype(int)
    df["day_of_month"] = df["full_date"].dt.day
    df["day_name"] = df["full_date"].dt.day_name()
    df["day_of_week"] = df["full_date"].dt.dayofweek + 1
    df["month"] = df["full_date"].dt.month
    df["month_name"] = df["full_date"].dt.month_name()
    df["quarter"] = df["full_date"].dt.quarter
    df["year"] = df["full_date"].dt.year
    df["is_weekend"] = df["day_of_week"].apply(lambda x: 1 if x in [6, 7] else 0)
    
    # Dòng Unknown
    unknown_row = pd.DataFrame([{
        "date_key": -1,
        "full_date": pd.NaT,
        "day_of_month": 0,
        "day_name": "Unknown",
        "day_of_week": 0,
        "month": 0,
        "month_name": "Unknown",
        "quarter": 0,
        "year": 0,
        "is_weekend": 0
    }])
    
    return pd.concat([unknown_row, df], ignore_index=True)

def load_dim_scd1(df_clean: pd.DataFrame, target_table: str, natural_key: str, sk_name: str, engine: Engine):
    """Nạp Bảng Chiều SCD Type 1 (Ghi đè/Cập nhật trực tiếp)."""
    logger.info(f"Đang nạp Bảng Chiều SCD1: [{target_table}]...")
    
    # Lấy dữ liệu hiện tại trong DB nếu đã tồn tại
    try:
        existing_df = pd.read_sql_table(target_table, con=engine, schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None)
        max_sk = existing_df[sk_name].max() if not existing_df.empty else 0
    except Exception:
        existing_df = pd.DataFrame()
        max_sk = 0

    if max_sk < 0 or pd.isna(max_sk):
        max_sk = 0

    # Lọc các bản ghi chưa có trong DW
    if not existing_df.empty:
        existing_keys = set(existing_df[natural_key].dropna())
        new_records = df_clean[~df_clean[natural_key].isin(existing_keys)].copy()
    else:
        new_records = df_clean.copy()

    if not new_records.empty:
        # Gán Surrogate Key tự tăng
        new_records[sk_name] = range(int(max_sk) + 1, int(max_sk) + 1 + len(new_records))
        
        # Nếu là lần nạp đầu tiên, chèn thêm dòng Unknown (SK = -1)
        if existing_df.empty:
            unknown_dict = {col: "Unknown" if df_clean[col].dtype == "object" else None for col in df_clean.columns}
            unknown_dict[sk_name] = -1
            unknown_dict[natural_key] = -1
            unknown_df = pd.DataFrame([unknown_dict])
            final_df = pd.concat([unknown_df, new_records], ignore_index=True)
        else:
            final_df = new_records

        final_df.to_sql(
            name=target_table,
            con=engine,
            schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
            if_exists="append" if not existing_df.empty else "replace",
            index=False
        )
        logger.info(f"---> [SCD1] Đã chèn {len(new_records):,} bản ghi mới vào [{target_table}].")
    else:
        logger.info(f"---> [SCD1] Không có bản ghi mới cho [{target_table}].")

def load_dim_player_scd2(df_players_clean: pd.DataFrame, engine: Engine):
    """Nạp Bảng Chiều Dim_Player với chính sách SCD Type 2."""
    target_table = "dim_player"
    logger.info(f"Đang nạp Bảng Chiều Dim_Player (SCD Type 2)...")
    
    today_str = date.today().strftime("%Y-%m-%d")

    try:
        existing_dim = pd.read_sql_table(target_table, con=engine, schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None)
    except Exception:
        existing_dim = pd.DataFrame()

    if existing_dim.empty:
        # Lần đầu tiên khởi tạo Dim_Player
        df = df_players_clean.copy()
        df["player_key"] = range(1, len(df) + 1)
        df["effective_date"] = "1900-01-01"
        df["expiry_date"] = "9999-12-31"
        df["is_current"] = 1

        # Chèn dòng Unknown (player_key = -1)
        unknown_player = {
            "player_key": -1,
            "player_id": -1,
            "player_name": "Unknown Player",
            "position": "Unknown",
            "height_band": "Unspecified",
            "effective_date": "1900-01-01",
            "expiry_date": "9999-12-31",
            "is_current": 1
        }
        df_final = pd.concat([pd.DataFrame([unknown_player]), df], ignore_index=True)

        df_final.to_sql(
            name=target_table,
            con=engine,
            schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
            if_exists="replace",
            index=False
        )
        logger.info(f"---> [SCD2] Khởi tạo Dim_Player thành công với {len(df_final):,} bản ghi.")
    else:
        # Xử lý cập nhật SCD Type 2 cho các lần nạp tiếp theo
        # 1. Phát hiện cầu thủ mới -> Insert
        # 2. Phát hiện thay đổi position / agent_name -> Đóng phiên bản cũ, chèn phiên bản mới
        current_players = existing_dim[existing_dim["is_current"] == 1]
        max_sk = existing_dim["player_key"].max()

        merged = df_players_clean.merge(
            current_players, on="player_id", how="left", suffixes=("_new", "_old")
        )

        # Cầu thủ mới hoàn toàn
        new_players = merged[merged["player_key"].isna()].copy()
        if not new_players.empty:
            new_players["player_key"] = range(int(max_sk) + 1, int(max_sk) + 1 + len(new_players))
            new_players["effective_date"] = today_str
            new_players["expiry_date"] = "9999-12-31"
            new_players["is_current"] = 1
            
            # Chọn các cột chuẩn theo schema
            cols_to_keep = [col for col in existing_dim.columns if col in new_players.columns]
            new_players[cols_to_keep].to_sql(
                name=target_table, con=engine, schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
                if_exists="append", index=False
            )
            logger.info(f"---> [SCD2] Đã chèn thêm {len(new_players):,} cầu thủ mới.")