"""Create a persistent factory-operation signing key without exposing its contents."""
import argparse
import os
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec
from app.services.device_authorization import private_pem, public_pem
from cryptography.hazmat.primitives import serialization

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',help='Private PEM output path; existing files are never overwritten')
    parser.add_argument('--public-header',help='Export a public verification header from an existing signing key')
    args=parser.parse_args()
    path=Path(args.path)
    if args.public_header:
        from app.services.device_inventory import c_string
        key=serialization.load_pem_private_key(path.read_bytes(),password=None)
        output=Path(args.public_header)
        output.parent.mkdir(parents=True,exist_ok=True)
        output.write_text('#pragma once\n#define DEVICE_SERVER_PUBLIC_KEY '+c_string(public_pem(key.public_key()))+'\n')
        print('Public verification header exported; it contains no private key.')
        return
    path.parent.mkdir(parents=True,exist_ok=True)
    try:
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError:
        parser.error('Signing key already exists; retain it and configure DEVICE_SIGNING_KEY_FILE.')
    with os.fdopen(fd,'w') as output:
        output.write(private_pem(ec.generate_private_key(ec.SECP256R1())))
    print('Signing key created. Back it up privately and configure DEVICE_SIGNING_KEY_FILE.')

if __name__=='__main__':
    main()
