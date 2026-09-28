from datetime import datetime
from pathlib import Path
import pandas as pd
from sqlalchemy import Engine, text
from config.settings import CURRENT_BATCH_ID, SCHEMA_STG_RAW
from src.utils.logger import logger

def load_csv_to_stg_raw(file_path: Path, table_name: str, engine: Engine, chunksize: int = 100_000):
    """
    Nạp dữ liệu từ file CSV vào bảng stg_raw.
    Tất cả các cột dữ liệu được đọc ở kiểu string (dtype=str).
    """
    logger.info(f"---> Bắt đầu nạp file [{file_path.name}] vào bảng [{table_name}]...")
    
    loaded_at = datetime.now()
    total_inserted = 0

    # Đọc file CSV theo từng Chunk để tối ưu bộ nhớ RAM
    chunk_iterator = pd.read_csv(
        file_path,
        dtype=str,             # Ép tất cả cột dữ liệu về kiểu Chuỗi
        keep_default_na=False, # Giữ nguyên chuỗi rỗng
        chunksize=chunksize
    )

    is_first_chunk = True

    for chunk in chunk_iterator:
        # Bổ sung 3 cột kỹ thuật (Audit Columns)
        chunk["batch_id"] = CURRENT_BATCH_ID
        chunk["loaded_at"] = loaded_at
        chunk["source_file"] = file_path.name

        # Nếu là chunk đầu tiên: ghi đè/tạo bảng mới (if_exists='replace')
        # Các chunk sau: ghi nối tiếp (if_exists='append')
        mode = "replace" if is_first_chunk else "append"
        
        # Sửa lại đoạn chunk.to_sql
        chunk.to_sql(
            name=table_name,
            con=engine,
            schema=SCHEMA_STG_RAW, # Đã đổi thành 'dbo' ở settings
            if_exists=mode,
            index=False
            # BỎ CÁI NÀY ĐI: method="multi" if "sqlite" in engine.dialect.name else None
        )
        
        total_inserted += len(chunk)
        is_first_chunk = False

    logger.info(f"---> [Thành công] Đã nạp tổng cộng {total_inserted:,} dòng vào [{table_name}].")
    return total_inserted