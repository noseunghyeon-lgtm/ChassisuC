#!/usr/bin/env python3
"""표준 라이브러리만으로 .xlsx 파싱 (openpyxl 미설치 환경용)."""
import sys, zipfile, re
import xml.etree.ElementTree as ET

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

def col_to_idx(ref):
    m = re.match(r'([A-Z]+)(\d+)', ref)
    letters = m.group(1)
    idx = 0
    for c in letters:
        idx = idx * 26 + (ord(c) - ord('A') + 1)
    return idx - 1

def load_shared_strings(z):
    out = []
    try:
        root = ET.fromstring(z.read('xl/sharedStrings.xml'))
    except KeyError:
        return out
    for si in root.findall(f'{NS}si'):
        # 여러 t(run) 합치기
        texts = [t.text or '' for t in si.iter(f'{NS}t')]
        out.append(''.join(texts))
    return out

def parse_sheet(z, sheet, shared):
    root = ET.fromstring(z.read(sheet))
    rows = []
    for row in root.iter(f'{NS}row'):
        cells = {}
        maxc = 0
        for c in row.findall(f'{NS}c'):
            ref = c.get('r')
            ci = col_to_idx(ref)
            t = c.get('t')
            v = c.find(f'{NS}v')
            is_el = c.find(f'{NS}is')
            if t == 's' and v is not None:
                val = shared[int(v.text)]
            elif is_el is not None:
                val = ''.join(x.text or '' for x in is_el.iter(f'{NS}t'))
            elif v is not None:
                val = v.text
            else:
                val = ''
            cells[ci] = val
            maxc = max(maxc, ci)
        rowlist = [cells.get(i, '') for i in range(maxc + 1)]
        rows.append(rowlist)
    return rows

def main():
    path = sys.argv[1]
    z = zipfile.ZipFile(path)
    shared = load_shared_strings(z)
    rows = parse_sheet(z, 'xl/worksheets/sheet1.xml', shared)
    print(f'총 {len(rows)} 행')
    print('=' * 80)
    for i, r in enumerate(rows):
        # 빈 셀 제거 표시
        cells = ' | '.join(str(x) for x in r)
        print(f'[{i:3}] {cells}')

if __name__ == '__main__':
    main()
