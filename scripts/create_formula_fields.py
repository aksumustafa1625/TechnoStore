import os
import subprocess
import json
import sys

TOKEN = os.environ.get("SF_ACCESS_TOKEN")
URL = os.environ.get("SF_INSTANCE_URL", "https://your-org.develop.my.salesforce.com")

if not TOKEN:
    sys.exit("SF_ACCESS_TOKEN env var required. Get one with: sf org display --target-org TechnoStore --json | jq -r .result.accessToken")

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
