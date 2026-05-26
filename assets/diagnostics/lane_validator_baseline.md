# Lane Validator Baseline

**Generated:** lane_validator_baseline.py
**Corpus:** assets/stories/traditional
**Validator threshold (KJV archaic markers):** see KJV_MIN_ARCHAIC_MARKERS

## Headline

- Files scanned: **1052**
- Files with at least one violation: **322** (30.6%)

## Violations by category

| Category | Count |
|---|---|
| WEB_CONTRACTION | 430 |
| WEB_ARCHAIC_BLEED | 115 |
| KJV_TOO_FEW_ARCHAIC_MARKERS | 36 |

## Per-batch (10-story bucket) summary

| Bucket | KJV files | KJV viol | WEB files | WEB viol |
|---|---|---|---|---|
| 800–809 | 6 | 0 | 15 | 6 |
| 810–819 | 0 | 0 | 9 | 3 |
| 820–829 | 0 | 0 | 24 | 10 |
| 830–839 | 0 | 0 | 15 | 8 |
| 1000–1009 | 24 | 16 | 24 | 25 |
| 1010–1019 | 10 | 0 | 10 | 0 |
| 1020–1029 | 11 | 0 | 11 | 0 |
| 1030–1039 | 16 | 2 | 16 | 2 |
| 1040–1049 | 4 | 0 | 4 | 0 |
| 1050–1059 | 12 | 2 | 12 | 0 |
| 1060–1069 | 18 | 2 | 18 | 0 |
| 1070–1079 | 6 | 0 | 6 | 0 |
| 1080–1089 | 30 | 0 | 40 | 38 |
| 1090–1099 | 30 | 2 | 58 | 127 |
| 1100–1109 | 25 | 2 | 28 | 16 |
| 1110–1119 | 16 | 2 | 16 | 0 |
| 1120–1129 | 1 | 0 | 12 | 4 |
| 1130–1139 | 0 | 0 | 10 | 0 |
| 1140–1149 | 0 | 0 | 10 | 0 |
| 1150–1159 | 0 | 0 | 10 | 5 |
| 1160–1169 | 0 | 0 | 10 | 7 |
| 1170–1179 | 0 | 0 | 10 | 4 |
| 1180–1189 | 0 | 0 | 10 | 6 |
| 1190–1199 | 0 | 0 | 10 | 7 |
| 1200–1209 | 0 | 0 | 10 | 2 |
| 1210–1219 | 0 | 0 | 10 | 5 |
| 1220–1229 | 0 | 0 | 10 | 12 |
| 1230–1239 | 0 | 0 | 10 | 8 |
| 1240–1249 | 0 | 0 | 10 | 14 |
| 1250–1259 | 0 | 0 | 11 | 4 |
| 1260–1269 | 0 | 0 | 10 | 8 |
| 1270–1279 | 0 | 0 | 10 | 5 |
| 1280–1289 | 0 | 0 | 10 | 4 |
| 1290–1299 | 0 | 0 | 10 | 4 |
| 1300–1309 | 0 | 0 | 10 | 4 |
| 1310–1319 | 0 | 0 | 10 | 6 |
| 1320–1329 | 0 | 0 | 10 | 2 |
| 1330–1339 | 0 | 0 | 10 | 5 |
| 1340–1349 | 0 | 0 | 10 | 11 |
| 1350–1359 | 0 | 0 | 10 | 8 |
| 1360–1369 | 0 | 0 | 10 | 6 |
| 1370–1379 | 0 | 0 | 10 | 5 |
| 1380–1389 | 0 | 0 | 10 | 7 |
| 1390–1399 | 0 | 0 | 10 | 8 |
| 1400–1409 | 0 | 0 | 10 | 4 |
| 1410–1419 | 0 | 0 | 10 | 2 |
| 1420–1429 | 0 | 0 | 10 | 6 |
| 1430–1439 | 0 | 0 | 10 | 4 |
| 1440–1449 | 0 | 0 | 10 | 3 |
| 1450–1459 | 0 | 0 | 10 | 0 |
| 1460–1469 | 0 | 0 | 10 | 2 |
| 1470–1479 | 4 | 0 | 10 | 4 |
| 1480–1489 | 16 | 2 | 16 | 13 |
| 1490–1499 | 21 | 2 | 21 | 14 |
| 1500–1509 | 14 | 0 | 14 | 2 |
| 1510–1519 | 21 | 2 | 21 | 36 |
| 1520–1529 | 13 | 2 | 13 | 59 |

## Notes

- Validator is currently WARN-only; this baseline is calibration data, NOT a list of stories to fix.
- High KJV_TOO_FEW_ARCHAIC_MARKERS count is expected; many legacy KJV stories rely on cadence/syntax rather than lexical markers. Threshold tuning will follow batch-level review.
- WEB violations (archaic bleed, contractions) are the more actionable signal — those indicate genuine lane drift.
