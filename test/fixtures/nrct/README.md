# nrct fixtures

Retrieved 2026-09-29 from
https://geoshape.ex.nii.ac.jp/nrct/dataset/nrct-20250719.csv — the
日本歴史地名大系 placename dataset (Heibonsha, published
machine-readable by ROIS-DS/NII geoshape; CC BY 4.0, DOI
10.20676/00000448; 80,502 data rows).

`nrct.csv` — the REAL first 30 lines (`head -n 30`: header + 29
Hokkaidō rows), byte-verbatim. Includes 鍛冶町 (id 010000040000),
whose 歴史地名 column carries a DIFFERENT historical name (鍛冶村) —
the extra-name-key case — plus centroid- and oketani-method rows.

Columns (header verbatim): id, 都道府県コード, 名称, 読み, 上位地名,
出典住所, 緯度, 経度, 推定手法, 歴史地名ID, 歴史地名, geolod_id.
