#!/usr/bin/python3
"""Set the Observium admin password."""

import argparse
import subprocess
import sys

from libinithooks.dialog_wrapper import Dialog
from mysqlconf import MySQL


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--pass', dest='password', help=argparse.SUPPRESS)
    source.add_argument('--pass-stdin', action='store_true',
                        help='read the new password from standard input')
    args = parser.parse_args()

    if args.pass_stdin:
        password = sys.stdin.read()
    elif args.password is not None:
        password = args.password
    else:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "Observium Password",
            "Enter new password for the Observium 'admin' account.")

    if not password:
        parser.error('password must not be empty')

    result = subprocess.run(
        [
            'php', '-r',
            'echo password_hash(stream_get_contents(STDIN), PASSWORD_DEFAULT);'
        ],
        input=password,
        check=True,
        capture_output=True,
        text=True,
    )
    password_hash = result.stdout
    if not password_hash:
        raise RuntimeError('PHP did not return a password hash')

    m = MySQL()
    m.execute(
        'UPDATE observium.users SET password=%s WHERE username=%s;',
        (password_hash, 'admin'),
    )


if __name__ == "__main__":
    main()
