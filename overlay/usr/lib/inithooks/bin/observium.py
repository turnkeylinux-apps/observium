#!/usr/bin/python3
"""Set Observium admin password

Option:
    --pass=     unless provided, will ask interactively

"""

import sys
import getopt

import crypt
from random import SystemRandom
import hashlib

from dialog_wrapper import Dialog
from mysqlconf import MySQL

def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h", ['help', 'pass='])
    except getopt.GetoptError as e:
        usage(e)

    password = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "Observium Password",
            "Enter new password for the Observium 'admin' account.")

    random = SystemRandom()
    salt = hashlib.sha1(str(random.random()).encode('utf8')).hexdigest()[:8]
    hash = crypt.crypt(password, "$1$" + salt + "$")

    m = MySQL()
    m.execute('UPDATE observium.users SET password=%s WHERE username=\"admin\";', (hash,))


if __name__ == "__main__":
    main()

