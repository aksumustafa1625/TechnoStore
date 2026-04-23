import subprocess
import json

TOKEN = "REDACTED-SESSION-TOKEN"
URL = "https://your-org.develop.my.salesforce.com"

fields = [
    ("OwnerName", 'Owner.FirstName & " " & Owner.LastName'),
    ("CustomerSignedByName", 'CustomerSigned.FirstName & " " & CustomerSigned.LastName'),
    ("CompanySignedByName", 'CompanySigned.FirstName & " " & CompanySigned.LastName'),
]

for name, formula in fields:
    payload = {
        "FullName": f"Contract.{name}__c",
        "Metadata": {
            "type": "Text",
            "label": name,
            "formula": formula,
            "formulaTreatBlanksAs": "BlankAsBlank"
        }
    }
    result = subprocess.run(
        [
            "curl", "-s", "-X", "POST",
            "-H", f"Authorization: Bearer {TOKEN}",
            "-H", "Content-Type: application/json",
            "-d", json.dumps(payload),
            f"{URL}/services/data/v63.0/tooling/sobjects/CustomField/"
        ],
        capture_output=True, text=True
    )
    print(f"{name}: {result.stdout}")
