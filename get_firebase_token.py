#!/usr/bin/env python3
"""
Fetch a fresh Firebase idToken (email/password account) for drma.ai
usage:
  ./get_firebase_token.py [path/to/fb_token.txt]
writes the idToken (plain JWT text) to the given path
"""
import base64
import json
import os
import random
import sys
import urllib.request

API_KEY = "AIzaSyDYBPfea0jgFMhjBzw4F1diqEl3KgP21xk"  # Firebase web api key from drma.ai bundle
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fb_token.txt"


def signup():
    rand = base64.b64encode(os.urandom(6)).decode().replace("+", "/")
    email = f"drma.farm{rand}{random.randint(1000,999999)}@proton.me"
    password = "Tr!" + str(random.randint(100000, 999999)) + "000pass"
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}"
    body = json.dumps({"email": email, "password": password, "returnSecureToken": True}).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        d = json.loads(resp.read().decode())
    print(f"[signup] {email}")
    print(f"[ok] localId: {d.get('localId')} | token bytes: {len(d.get('idToken',''))}")
    return d.get("idToken", "")


def main():
    tok = signup()
    if not tok:
        print("[err] no token")
        sys.exit(1)
    with open(OUT, "w") as f:
        f.write(tok)
    print(f"token saved to: {OUT}")


if __name__ == "__main__":
    main()
