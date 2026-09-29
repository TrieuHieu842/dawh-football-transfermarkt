import hashlib
from pathlib import Path
import pandas as pd
from src.utils.logger import logger

def get_file_checksum(file_path: Path) -> str:
    """Tính mã băm MD5 của file để kiểm tra tính toàn vẹn."""
    hasher = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def inspect_csv_file(file_path: Path):
    """Kiểm tra số dòng và mã MD5 của file CSV nguồn."""
    if not file_path.exists():
        raise FileNotFoundError(f"Không tìm thấy file nguồn: {file_path}")
    
    checksum = get_file_checksum(file_path)
    # Đếm số dòng nhanh
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        row_count = sum(1 for _ in f) - 1 # Trừ dòng header
        
    logger.info(f"File [{file_path.name}] - Số dòng: {row_count:,} | MD5: {checksum}")
    return row_count, checksum