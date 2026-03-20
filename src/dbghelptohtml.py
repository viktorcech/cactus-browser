# version 2
from __future__ import print_function

import sys, os, re, codecs
from argparse import ArgumentParser

try:
    import html
except ImportError:
    import cgi as html

parser = ArgumentParser(description="Convert Altirra debugger help to an HTML file")
parser.add_argument("path", help="path to the Altirra source top directory")
parser.add_argument("-a", "--arrows", help="add twisty arrows", action="store_true")
parser.add_argument("-p", "--printable", help="fully expanded, links in black", action="store_true")
group = parser.add_mutually_exclusive_group()
group.add_argument("-e", "--extract", help="add version number found in source to titles", action="store_true")
group.add_argument("-v", "--version", help="add provided version number to titles", action="store")
args = parser.parse_args()

help_path = os.path.join(args.path, "src/Altirra/res/dbghelp.txt")
version_path = os.path.join(args.path, "src/Altirra/res/AltirraVersion.rc")
if not os.path.exists(help_path) or not os.path.exists(version_path):
    sys.exit("Not a valid source directory - the files aren't in the expected place.")

help_file = open(help_path, "r")

# read and convert from UTF-16
version_file = codecs.open(version_path, "r", 'utf-16')

a = b = c = "0"
version = ""
copy = ""
for line in version_file:
    line = line.strip()
    if line.startswith("FILEOS"):
        a = re.findall("^.*x(\d*)L$", line)[0]
    if line.startswith("FILETYPE"):
        b = re.findall("^.*x(\d*)L$", line)[0]
    if line.startswith("FILESUBTYPE"):
        c = re.findall("^.*x(\d*)L$", line)[0]
    if line.startswith('VALUE "LegalCopyright"'):
        copy = re.findall('^.*,\s*"(.*)"$', line)[0]

if args.extract:
    version = "{}.{}{}".format(a, b, c)
elif args.version:
    version = args.version

default_state = ""
if args.printable:
    default_state = " open"

inside = False
tail = False
see_also = False

print("<html lang='en'>")
print("<head>")
print("<title>Altirra {} Debugger Command Reference</title>".format(version))
print("<style>")
print("hr {border:none;border-top:1px solid darkgray}")
print("details > summary {cursor:pointer;outline:none;margin-left:2px;padding-left:2px}")
if not args.arrows:
    print("details > summary {list-style:none}")
    print("details > summary::-webkit-details-marker {display:none}")
print("details > summary:hover {background-color:#DDDDDD}")
print("details > summary:focus {margin-left:0;border-left:2px solid -moz-mac-focusring}")
print("details > summary:focus {border-left:2px solid -webkit-focus-ring-color}")
print("details > summary .cmd {font-weight:bold;display:inline-block;min-width:6em;margin-right:1em}")
if args.printable:
    print("a {color:black;text-decoration:none}")
print("</style>")
print("</head>")
print("<body>")
print("<h3>Altirra {} Debugger Command Reference</h3>".format(version))
for line in help_file:
    if line.strip() == "":
        see_also = False
    if line[0] == "+" or line[0] == "^":
        line = line[2:].rstrip("\r\n")
        if inside:
            if not has_description and not args.printable:
                print("    Intentionally Blank")
            print("</pre>\n</a>\n</details>")
        inside = True
        a = re.findall("^(.*?[^,])\s+(\w.*)$", line)
        alist = a[0][0].split(", ")
        print("<details{}>".format(default_state))
        print("<summary>".format(default_state))
        print("<span class='cmd'>{}</span>".format(html.escape(a[0][0])))
        print(html.escape(a[0][1].rstrip('\r\n')))
        print("</summary>")
        print("<a id='{}'>".format(html.escape(alist[0])))
        print("<pre>")
        has_description = False
        first_line = True
    elif line[0] == ".":
        if not tail:
            if not has_description:
                print("    Intentionally Blank")
            print("</pre>\n</a>\n</details>")
            if not args.printable:
                print("<hr/>")
            print("<pre>")
            first_line = True
        tail = True
        if line.strip() != "." or not first_line:
            print(html.escape(line[2:].rstrip('\r\n')))
        first_line = False
    elif line.strip().startswith("See also:") or see_also:
        if see_also:
            preamble = line[0:(len(line) - len(line.lstrip()))]
            refs = line.strip().split(",")
        else:
            parts = line.split(":")
            preamble = parts[0] + ": "
            refs = parts[1].split(",")
        if refs[-1].strip() == "":
            see_also = True
            refs.pop()
        links = []
        for ref in refs:
            links.append("<a href='#{}'>{}</a>".format(ref.split()[0], ref.strip()))
        print(preamble, end="")
        print(*links, sep=", ")
    elif line[0] != ">":
        line = line.rstrip('\r\n')
        if line != "" or not first_line:
            print(html.escape(line))
        if line != "":
            has_description = True
            first_line = False

if tail:
    print("</pre>")
    if not args.printable:
        print("<hr/>")

if copy:
    print
    print("<small>{}</small>".format(copy))

print("</body>")
print("</html>")
