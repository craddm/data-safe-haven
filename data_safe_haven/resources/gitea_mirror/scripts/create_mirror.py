import argparse

import requests
from requests.auth import HTTPBasicAuth

parser = argparse.ArgumentParser()
parser.add_argument(
    'username'
)
parser.add_argument(
    'password'
)
parser.add_argument(
    'name'
)
parser.add_argument(
    'address'
)
args = parser.parse_args()

# gitea_host = "http://gitea_mirror.local"
gitea_host = "http://localhost:3000"
api_root = "/api/v1"
migrate_path = "/repos/migrate"
extra_data = {
    "description": f"Read-only mirror of {args.address}",
    "mirror": True,
    "mirror_interval": "10m",
}

auth = HTTPBasicAuth(
    username=args.username,
    password=args.password,
)

print(
    {"clone_addr": args.address, "repo_name": args.name} | extra_data
)

response = requests.post(
    auth=auth,
    data={
        "clone_addr": args.address,
        "repo_name": args.name,
    } | extra_data,
    url=gitea_host + api_root + migrate_path,
)

print(response.json())
response.raise_for_status()
