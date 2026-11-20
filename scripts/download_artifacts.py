#!/usr/bin/env python3
import json
import os
import sys
import urllib.request

def main():
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GH_REPO") or os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")

    if not token or not repo or not run_id:
        print("Missing required env vars: GH_TOKEN, GH_REPO, GITHUB_RUN_ID", file=sys.stderr)
        sys.exit(1)

    stage_dir = sys.argv[1] if len(sys.argv) > 1 else "stage"
    os.makedirs(stage_dir, exist_ok=True)

    list_url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}/artifacts"
    req = urllib.request.Request(
        list_url,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())

    artifacts = data.get("artifacts", [])
    print(f"Found {len(artifacts)} artifact(s) for run {run_id}")

    class NoAuthRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
            if new_req and "Authorization" in new_req.headers:
                del new_req.headers["Authorization"]
            return new_req

    opener = urllib.request.build_opener(NoAuthRedirect)

    for art in artifacts:
        name = art["name"]
        art_id = art["id"]
        dl_url = f"https://api.github.com/repos/{repo}/actions/artifacts/{art_id}/zip"
        print(f"Downloading {name} ({art_id})...")
        art_req = urllib.request.Request(dl_url, headers={"Authorization": f"Bearer {token}"})
        with opener.open(art_req) as resp:
            content = resp.read()
        dest = os.path.join(stage_dir, name)
        with open(dest, "wb") as f:
            f.write(content)
        print(f"  -> Saved {dest} ({len(content)} bytes)")

if __name__ == "__main__":
    main()
