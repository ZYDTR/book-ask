#!/usr/bin/env python3
import plistlib
import sys
from pathlib import Path

info = {
    "CFBundleName": "读书提问", "CFBundleDisplayName": "读书提问", "CFBundleExecutable": "BookAsk",
    "CFBundleIdentifier": "com.zydtr.book-ask", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
    "CFBundleShortVersionString": "0.1.0", "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": True,
    "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoads": True},
    "NSServices": [{"NSMenuItem": {"default": "读书提问"}, "NSMessage": "askWithText", "NSPortName": "读书提问",
                    "NSSendTypes": ["NSStringPboardType", "public.utf8-plain-text"], "NSReturnTypes": [],
                    "NSKeyEquivalent": {"default": "E"}, "NSTimeout": "10000"}],
}
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
