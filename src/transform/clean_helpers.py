import numpy as np
import pandas as pd

def clean_string_column(series: pd.Series) -> pd.Series:
    """Làm sạch chuỗi: TRIM, xóa ký tự \xa0, chuyển chuỗi rỗng/mờ thành None/NaN."""
    if series is None:
        return series
    cleaned = (
        series.astype(str)
        .str.replace(r"\xa0", " ", regex=True)
        .str.strip()
    )
    # Chuyển các giá trị rỗng/không xác định về NaN
    cleaned = cleaned.replace(["", "nan", "None", "null", "NULL"], np.nan)
    return cleaned

def parse_date_column(series: pd.Series) -> pd.Series:
    """Chuyển đổi chuỗi ngày tháng về dạng chuẩn YYYY-MM-DD (bỏ phần giờ 00:00:00)."""
    cleaned_str = clean_string_column(series)
    return pd.to_datetime(cleaned_str, errors="coerce").dt.date

def safe_to_numeric(series: pd.Series, dtype="float64") -> pd.Series:
    """Ép kiểu sang số an toàn, nếu lỗi thì gán NaN."""
    cleaned_str = clean_string_column(series)
    return pd.to_numeric(cleaned_str, errors="coerce").astype(dtype)

def categorize_height(height_cm: pd.Series) -> pd.Series:
    """Phân nhóm chiều cao cầu thủ."""
    conditions = [
        height_cm < 175,
        (height_cm >= 175) & (height_cm < 185),
        (height_cm >= 185) & (height_cm < 195),
        height_cm >= 195,
    ]
    choices = ["Dưới 175cm", "175 - 184cm", "185 - 194cm", "Từ 195cm trở lên"]
    return pd.Series(np.select(conditions, choices, default="Unspecified"), index=height_cm.index)

def categorize_fee(fee_eur: pd.Series) -> pd.Series:
    """Phân nhóm phí chuyển nhượng."""
    conditions = [
        fee_eur == 0,
        (fee_eur > 0) & (fee_eur < 5_000_000),
        (fee_eur >= 5_000_000) & (fee_eur < 20_000_000),
        (fee_eur >= 20_000_000) & (fee_eur < 50_000_000),
        fee_eur >= 50_000_000,
    ]
    choices = ["Free Transfer", "Dưới 5 triệu €", "5 - 20 triệu €", "20 - 50 triệu €", "Trên 50 triệu €"]
    return pd.Series(np.select(conditions, choices, default="Unknown"), index=fee_eur.index)