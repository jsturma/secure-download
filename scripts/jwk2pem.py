#!/usr/bin/env python3
# jwk2pem.py
# usage: sudo python3 jwk2pem.py jwks.json /etc/nginx/jwks
import sys, os, json, base64
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

def b64u_to_int(b64u):
    data = b64u + '=' * ((4 - len(b64u) % 4) % 4)
    return int.from_bytes(base64.urlsafe_b64decode(data), 'big')

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: jwk2pem.py jwks.json outdir")
        sys.exit(2)
    jwks_file = sys.argv[1]
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    with open(jwks_file, 'r') as f:
        jwks = json.load(f)
    for key in jwks.get("keys", []):
        kid = key.get("kid") or "kid_unknown"
        kty = key.get("kty")
        if kty != "RSA":
            print("Skipping non RSA key", kid)
            continue
        n = key["n"]
        e = key.get("e", "AQAB")
        n_int = b64u_to_int(n)
        e_int = b64u_to_int(e)
        pub = rsa.RSAPublicNumbers(e_int, n_int).public_key()
        pem = pub.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        out_path = os.path.join(outdir, kid + ".pem")
        with open(out_path, "wb") as out:
            out.write(pem)
        print("Wrote", out_path)
