from pypdf import PdfReader
r = PdfReader(r'C:\Users\DELL\Documents\Projects\TechnoStore\TechnoStore_MSA_00000301_FRESH.pdf')
print('Pages:', len(r.pages))
for i, p in enumerate(r.pages):
    print(f'\n--- PAGE {i+1} ---')
    print(p.extract_text())
